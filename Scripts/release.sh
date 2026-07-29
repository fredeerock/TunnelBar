#!/bin/bash
# One-command release helper for TunnelBar.
#
# What it does:
#   1) validates release prerequisites
#   2) pushes main (if needed)
#   3) creates and pushes the tag (if missing)
#   4) builds signed + notarized app via build-app.sh
#   5) verifies signature and stapled ticket
#   6) creates or updates the GitHub release asset
set -euo pipefail

cd "$(dirname "$0")/.."

usage() {
  cat <<'EOF'
Usage:
  ./Scripts/release.sh <tag> [title]

Examples:
  ./Scripts/release.sh v1.0.3
  ./Scripts/release.sh v1.0.3 "TunnelBar v1.0.3"

Environment:
  Required:
    DEVELOPER_ID   e.g. Developer ID Application: Your Name (TEAMID)

  Notarization (choose one):
    AC_PROFILE
    or AC_APPLE_ID + AC_TEAM_ID + AC_PASSWORD
EOF
}

fail() {
  echo "error: $*" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "missing required command: $1"
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

TAG="${1:-}"
TITLE="${2:-}"

[[ -n "$TAG" ]] || {
  usage
  fail "tag is required"
}

if [[ -z "$TITLE" ]]; then
  TITLE="TunnelBar $TAG"
fi

if ! [[ "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  fail "tag must look like v1.2.3"
fi

need_cmd git
need_cmd gh
need_cmd swift
need_cmd codesign
need_cmd xcrun

if [[ -z "${DEVELOPER_ID:-}" ]]; then
  fail "DEVELOPER_ID is not set"
fi

if [[ -z "${AC_PROFILE:-}" ]]; then
  if [[ -z "${AC_APPLE_ID:-}" || -z "${AC_TEAM_ID:-}" || -z "${AC_PASSWORD:-}" ]]; then
    fail "set AC_PROFILE, or set AC_APPLE_ID + AC_TEAM_ID + AC_PASSWORD"
  fi
fi

if ! gh auth status >/dev/null 2>&1; then
  fail "gh is not authenticated. Run: gh auth login"
fi

if [[ "$(git rev-parse --abbrev-ref HEAD)" != "main" ]]; then
  fail "you must run releases from main"
fi

if [[ -n "$(git status --porcelain)" ]]; then
  fail "working tree is not clean. Commit or stash changes first"
fi

echo "==> Fetching tags from origin..."
git fetch --tags origin >/dev/null

echo "==> Pushing main..."
git push origin main

TAG_EXISTS_LOCAL=0
TAG_EXISTS_REMOTE=0
if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
  TAG_EXISTS_LOCAL=1
fi
if git ls-remote --exit-code --tags origin "refs/tags/$TAG" >/dev/null 2>&1; then
  TAG_EXISTS_REMOTE=1
fi

if [[ "$TAG_EXISTS_LOCAL" -eq 0 && "$TAG_EXISTS_REMOTE" -eq 0 ]]; then
  echo "==> Creating tag $TAG..."
  git tag -a "$TAG" -m "$TITLE"
  echo "==> Pushing tag $TAG..."
  git push origin "$TAG"
elif [[ "$TAG_EXISTS_LOCAL" -eq 1 && "$TAG_EXISTS_REMOTE" -eq 0 ]]; then
  echo "==> Pushing existing local tag $TAG..."
  git push origin "$TAG"
elif [[ "$TAG_EXISTS_LOCAL" -eq 0 && "$TAG_EXISTS_REMOTE" -eq 1 ]]; then
  fail "tag exists on origin but not locally. Run: git fetch --tags origin"
else
  echo "==> Tag $TAG already exists locally and on origin."
fi

echo "==> Building signed + notarized app..."
./Scripts/build-app.sh

ZIP="build/TunnelBar.zip"
APP="build/TunnelBar.app"
[[ -f "$ZIP" ]] || fail "expected release zip not found: $ZIP"
[[ -d "$APP" ]] || fail "expected app bundle not found: $APP"

echo "==> Verifying Developer ID signature..."
SIGN_INFO="$(codesign -dv --verbose=4 "$APP" 2>&1 || true)"
if ! grep -q "Authority=Developer ID Application" <<< "$SIGN_INFO"; then
  echo "$SIGN_INFO" >&2
  fail "app is not signed with a Developer ID identity"
fi

echo "==> Verifying stapled ticket..."
if ! xcrun stapler validate "$APP" >/dev/null 2>&1; then
  fail "stapler validation failed; app does not appear notarized/stapled"
fi

if gh release view "$TAG" >/dev/null 2>&1; then
  echo "==> Updating existing release asset..."
  gh release upload "$TAG" "$ZIP" --clobber
  echo "==> Release updated: $TAG"
else
  echo "==> Creating GitHub release..."
  gh release create "$TAG" "$ZIP" --title "$TITLE" --generate-notes
  echo "==> Release created: $TAG"
fi

echo "==> Done."
gh release view "$TAG" --json url -q .url
