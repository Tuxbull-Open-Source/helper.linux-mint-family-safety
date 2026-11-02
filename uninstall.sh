#!/usr/bin/env bash
# Remove only artifacts installed by install.sh. Existing UFW and APT settings remain untouched.
set -Eeuo pipefail

[[ ${EUID} -eq 0 ]] || { printf '%s\n' 'Run with: sudo ./uninstall.sh' >&2; exit 1; }

systemctl disable --now family-safety-enforce.service 2>/dev/null || true
rm -f /etc/systemd/system/family-safety-enforce.service
rm -rf /usr/local/lib/family-safety
  # Remove only the value this bundle owns; preserve other Firefox policies.
  python3 - <<'PY'
import json
import os

path = "/etc/firefox/policies/policies.json"
if not os.path.exists(path):
    raise SystemExit(0)
with open(path, encoding="utf-8") as fh:
    data = json.load(fh)
policies = data.get("policies")
if not isinstance(policies, dict):
    raise SystemExit(f"{path}: expected a 'policies' object; leaving it untouched")
policies.pop("DNSOverHTTPS", None)
if policies:
    temporary = f"{path}.tmp"
    with open(temporary, "w", encoding="utf-8") as fh:
        json.dump(data, fh, indent=2, sort_keys=True)
        fh.write("\n")
    os.chmod(temporary, 0o644)
    os.replace(temporary, path)
else:
    os.unlink(path)
PY
rmdir --ignore-fail-on-non-empty /etc/firefox/policies 2>/dev/null || true
systemctl daemon-reload
printf '%s\n' 'Removed the family-safety service and Firefox DNS-over-HTTPS policy.'
printf '%s\n' 'UFW rules, automatic-update settings, packages, and NetworkManager DNS profiles were deliberately preserved.'
printf '%s\n' 'To restore DNS, edit the affected connection(s) in Network settings or run nmcli manually.'
