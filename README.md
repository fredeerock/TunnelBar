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

## Requirements

- macOS 13 (Ventura) or newer
- [Homebrew](https://brew.sh) (used to install `openconnect`)
- Xcode Command Line Tools to build (`xcode-select --install`) — the full Xcode
  IDE is not required

## Build

```sh
./Scripts/build-app.sh
```

This produces `build/TunnelBar.app`. Move it to `/Applications`.

## Usage

1. Launch the app — a shield icon appears in the menu bar.
2. Open **Settings…** and click **Install Dependencies** (asks for your macOS
   password once, via a native dialog).
3. Enter your VPN gateway address and click **Connect**, then sign in.
4. Connect or disconnect from the menu-bar icon whenever you like.

## Notes

- The app is ad-hoc signed, not notarized. The first time you open it,
  right-click the app → **Open** to get past Gatekeeper.
- `openconnect` logs are written to `/var/log/gp-vpn-gui.log`.
