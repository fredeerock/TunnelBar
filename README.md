# TunnelBar

A menu-bar GUI for [`openconnect`](https://www.infradead.org/openconnect/) on
macOS. It signs you into a SAML-based VPN gateway and brings up the tunnel.

It handles the SAML web login in a native window, hands the resulting cookie to
`openconnect`, and lets you connect or disconnect from the menu bar.

## Features

- Menu-bar icon to connect and disconnect at any time
- Native SAML login window (no external browser)
- One-click **Install Dependencies** that installs `openconnect` and a
  privileged helper
- Remembers your last gateway address

## Install

Download the latest **TunnelBar.zip** from
[Releases](https://github.com/fredeerock/TunnelBar/releases), unzip it, and drag
`TunnelBar.app` into `/Applications`. The release is signed and notarized, so it
opens with a normal double-click — no Gatekeeper warning.

## Requirements

- macOS 13 (Ventura) or newer
- [Homebrew](https://brew.sh) (used to install `openconnect`)
- Xcode Command Line Tools to build (`xcode-select --install`) — the full Xcode
  IDE is not required

## Build

```sh
./Scripts/build-app.sh
```

This produces `build/TunnelBar.app` (ad-hoc signed). Move it to `/Applications`.

To build a signed + notarized app, set your Developer ID and notary profile:

```sh
DEVELOPER_ID="Developer ID Application: Your Name (TEAMID)" \
AC_PROFILE=tunnelbar \
./Scripts/build-app.sh
```

Create the notary profile once with
`xcrun notarytool store-credentials tunnelbar --apple-id <id> --team-id <TEAMID>`.

## Usage

1. Launch the app — a shield icon appears in the menu bar.
2. Open **Settings…** and click **Install Dependencies** (asks for your macOS
   password once, via a native dialog).
3. Enter your VPN gateway address and click **Connect**, then sign in.
4. Connect or disconnect from the menu-bar icon whenever you like.

## Notes

- Release builds are notarized, so they open with a double-click. An ad-hoc
  local build needs a right-click → **Open** the first time.
- `openconnect` logs are written to `/var/log/gp-vpn-gui.log`.
