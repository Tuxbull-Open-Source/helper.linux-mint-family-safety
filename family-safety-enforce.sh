#!/usr/bin/env bash
# Enforce baseline family-safety settings on Linux Mint / Ubuntu desktops.
# Managed by linux-mint-family-safety/install.sh.
set -Eeuo pipefail
IFS=$'\n\t'
umask 022

readonly DNS4='185.228.168.168,185.228.169.168'
readonly DNS6='2a0d:2a00:1::,2a0d:2a00:2::'
readonly LOG_TAG='family-safety-enforce'

log() {
  logger -t "$LOG_TAG" -- "$*"
  printf '%s: %s\n' "$LOG_TAG" "$*"
}

die() {
  log "ERROR: $*"
  exit 1
}

require_root() {
  [[ ${EUID} -eq 0 ]] || die 'Must run as root.'
}

require_supported_os() {
  [[ -r /etc/os-release ]] || die '/etc/os-release is missing.'
  # shellcheck disable=SC1091
  . /etc/os-release
  case "${ID:-}" in
    linuxmint|ubuntu) ;;
    *) die "Unsupported operating system: ${ID:-unknown}." ;;
  esac
}

ensure_packages() {
  local package
  local -a missing=()
  for package in ufw unattended-upgrades; do
    dpkg-query -W -f='${db:Status-Status}\n' "$package" 2>/dev/null | grep -qx installed || missing+=("$package")
  done

  if ((${#missing[@]})); then
    log "Installing missing packages: ${missing[*]}"
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y --no-install-recommends "${missing[@]}"
  fi
}

configure_automatic_security_updates() {
  install -d -m 0755 /etc/apt/apt.conf.d
  cat > /etc/apt/apt.conf.d/52family-safety-auto-upgrades <<'EOF'
// Managed by family-safety-enforce. This dedicated file does not replace
// distribution or administrator configuration files.
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF
  systemctl enable --now apt-daily.timer apt-daily-upgrade.timer
}

configure_firewall() {
  # Do not reset UFW: preserve any explicit rules the administrator added.
  ufw default deny incoming
  ufw default allow outgoing
  ufw --force enable
}

configure_networkmanager_dns() {
  command -v nmcli >/dev/null 2>&1 || die 'NetworkManager (nmcli) is required.'

  local uuid type device
  local configured=0
  while IFS=: read -r uuid type device; do
    [[ -n "$uuid" && -n "$device" ]] || continue
    case "$type" in
      802-11-wireless|802-3-ethernet)
        nmcli connection modify uuid "$uuid" \
          ipv4.ignore-auto-dns yes ipv4.dns "$DNS4" \
          ipv6.ignore-auto-dns yes ipv6.dns "$DNS6"
        # Apply to the active interface without reconnecting it. A future
        # reconnect also gets the persistent profile settings above.
        nmcli device reapply "$device" || log "DNS profile set; reapply deferred for $device."
        configured=$((configured + 1))
        ;;
    esac
  done < <(nmcli -t -f UUID,TYPE,DEVICE connection show --active)

  ((configured > 0)) || log 'No active Wi-Fi or Ethernet connection found; DNS will be applied when one is active at the next boot.'
}

configure_firefox() {
  local policy_file='/etc/firefox/policies/policies.json'
  install -d -m 0755 /etc/firefox/policies
  # Preserve unrelated organization/administrator policies while enforcing
  # only the DNS-over-HTTPS setting owned by this bundle.
  python3 - "$policy_file" <<'PY'
import json
import os
import sys

path = sys.argv[1]
data = {}
if os.path.exists(path):
    with open(path, encoding="utf-8") as fh:
        data = json.load(fh)
if not isinstance(data, dict):
    raise SystemExit(f"{path}: top-level JSON value must be an object")
policies = data.setdefault("policies", {})
if not isinstance(policies, dict):
    raise SystemExit(f"{path}: 'policies' must be an object")
policies["DNSOverHTTPS"] = {"Enabled": False, "Locked": True}
temporary = f"{path}.tmp"
with open(temporary, "w", encoding="utf-8") as fh:
    json.dump(data, fh, indent=2, sort_keys=True)
    fh.write("\n")
os.chmod(temporary, 0o644)
os.replace(temporary, path)
PY
}

main() {
  require_root
  require_supported_os
  ensure_packages
  configure_automatic_security_updates
  configure_firewall
  configure_networkmanager_dns
  configure_firefox
  log 'Family-safety baseline enforced successfully.'
}

main "$@"
