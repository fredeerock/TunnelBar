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
DNS_BACKUP=/var/run/gp-vpn-gui.dnsbackup

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
    local pid
    pid="$(cat "$PIDFILE" 2>/dev/null || true)"
    if [ -n "$pid" ]; then
      kill -INT "$pid" 2>/dev/null || true
      for _ in {1..20}; do
        if ! kill -0 "$pid" 2>/dev/null; then
          break
        fi
        sleep 0.1
      done
    fi
    rm -f "$PIDFILE"
  fi

  # If a stale openconnect process is still running, stop it gracefully.
  pkill -INT -x openconnect 2>/dev/null || true
}

network_service_for_interface() {
  local ifname="$1"
  /usr/sbin/networksetup -listnetworkserviceorder | \
    /usr/bin/awk -v iface="$ifname" '
      /\(Hardware Port: / {
        line = $0
        sub(/^\([0-9]+\) /, "", line)
        service = line
      }
      $0 ~ "Device: " iface "\\)" {
        print service
        exit
      }
    '
}

backup_dns() {
  local ifname service
  ifname="$(/usr/sbin/route -n get default 2>/dev/null | /usr/bin/awk '/interface:/{print $2; exit}')"
  if [ -z "$ifname" ]; then
    return 0
  fi

  service="$(network_service_for_interface "$ifname")"
  if [ -z "$service" ]; then
    return 0
  fi

  local dns
  dns="$(/usr/sbin/networksetup -getdnsservers "$service" 2>/dev/null || true)"

  if echo "$dns" | /usr/bin/grep -q "There aren't any DNS Servers set on"; then
    printf '%s\t%s\n' "$service" "__EMPTY__" > "$DNS_BACKUP"
    return 0
  fi

  # Collapse multi-line DNS output into a single tab-separated row.
  {
    printf '%s' "$service"
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      printf '\t%s' "$line"
    done <<< "$dns"
    printf '\n'
  } > "$DNS_BACKUP"
}

restore_dns() {
  [ -f "$DNS_BACKUP" ] || return 0

  local service
  service="$(/usr/bin/cut -f1 "$DNS_BACKUP")"
  [ -n "$service" ] || { rm -f "$DNS_BACKUP"; return 0; }

  local data
  data="$(/usr/bin/cut -f2- "$DNS_BACKUP")"

  if [ "$data" = "__EMPTY__" ] || [ -z "$data" ]; then
    /usr/sbin/networksetup -setdnsservers "$service" empty >/dev/null 2>&1 || true
  else
    local -a dns_args
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      dns_args+=("$line")
    done < <(/usr/bin/tr '\t' '\n' <<< "$data")

    if [ "${#dns_args[@]}" -gt 0 ]; then
      /usr/sbin/networksetup -setdnsservers "$service" "${dns_args[@]}" >/dev/null 2>&1 || true
    else
      /usr/sbin/networksetup -setdnsservers "$service" empty >/dev/null 2>&1 || true
    fi
  fi

  rm -f "$DNS_BACKUP"
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
    restore_dns
    backup_dns
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
    stop_existing
    restore_dns
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
