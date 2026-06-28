import Foundation

/// Source for the privileged helper script. It is written to a temp file and
/// installed (root-owned, 0755) at `/usr/local/libexec/gp-vpn-helper` during
/// "Install Dependencies". Only this exact path is granted passwordless sudo,
/// and every argument is validated before use, so the elevated surface is tiny.
let helperScriptSource = #"""
#!/bin/bash
set -euo pipefail

PIDFILE=/var/run/gp-vpn-gui.pid
LOGFILE=/var/log/gp-vpn-gui.log

find_openconnect() {
  for p in /opt/homebrew/bin/openconnect /usr/local/bin/openconnect /usr/bin/openconnect; do
    if [ -x "$p" ]; then
      echo "$p"
      return 0
    fi
  done
  return 1
}

stop_existing() {
  if [ -f "$PIDFILE" ]; then
    kill -INT "$(cat "$PIDFILE")" 2>/dev/null || true
    rm -f "$PIDFILE"
  fi
}

cmd="${1:-}"
case "$cmd" in
  connect)
    server="${2:-}"
    user="${3:-}"
    usergroup="${4:-gateway:prelogin-cookie}"

    if ! [[ "$server" =~ ^[A-Za-z0-9.-]+$ ]]; then
      echo "invalid server" >&2
      exit 2
    fi
    if ! [[ "$usergroup" =~ ^[A-Za-z0-9:_-]+$ ]]; then
      echo "invalid usergroup" >&2
      exit 2
    fi

    oc="$(find_openconnect)" || { echo "openconnect not found" >&2; exit 3; }

    stop_existing
    # The prelogin cookie is read from stdin via --passwd-on-stdin.
    "$oc" --protocol=gp \
          --user="$user" \
          --os=mac-intel \
          --usergroup="$usergroup" \
          --passwd-on-stdin \
          --background \
          --pid-file="$PIDFILE" \
          "$server" >>"$LOGFILE" 2>&1
    ;;

  disconnect)
    if [ -f "$PIDFILE" ]; then
      kill -INT "$(cat "$PIDFILE")" 2>/dev/null || true
      rm -f "$PIDFILE"
    else
      pkill -INT -x openconnect 2>/dev/null || true
    fi
    ;;

  status)
    if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
      echo connected
    else
      echo disconnected
    fi
    ;;

  *)
    echo "usage: gp-vpn-helper {connect <server> <user> [usergroup]|disconnect|status}" >&2
    exit 1
    ;;
esac
"""#
