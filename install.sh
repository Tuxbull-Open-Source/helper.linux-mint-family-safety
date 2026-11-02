#!/usr/bin/env bash
# Install the family-safety enforcement script and its boot-time systemd unit.
set -Eeuo pipefail
IFS=$'\n\t'
umask 022

readonly INSTALL_DIR='/usr/local/lib/family-safety'
readonly ENFORCER="$INSTALL_DIR/family-safety-enforce.sh"
readonly UNIT='/etc/systemd/system/family-safety-enforce.service'
readonly SOURCE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"

[[ ${EUID} -eq 0 ]] || { printf '%s\n' 'Run with: sudo ./install.sh' >&2; exit 1; }
[[ -f "$SOURCE_DIR/family-safety-enforce.sh" ]] || { printf '%s\n' 'family-safety-enforce.sh must be next to install.sh.' >&2; exit 1; }

install -d -m 0755 "$INSTALL_DIR"
install -m 0755 "$SOURCE_DIR/family-safety-enforce.sh" "$ENFORCER"

cat > "$UNIT" <<EOF
[Unit]
Description=Enforce family-safety baseline (DNS, firewall, browser policy)
Wants=network-online.target
After=network-online.target NetworkManager.service
ConditionPathExists=/usr/bin/nmcli

[Service]
Type=oneshot
ExecStart=$ENFORCER
# The unit runs at every boot. The journal retains the exact error if a run fails.
Restart=no

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable family-safety-enforce.service
systemctl start family-safety-enforce.service
systemctl --no-pager --full status family-safety-enforce.service
