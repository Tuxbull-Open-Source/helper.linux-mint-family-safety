# Linux Mint family-safety boot enforcement

This bundle installs a small systemd service that enforces a baseline on every boot (and once during installation). It is designed for Linux Mint / Ubuntu desktops using NetworkManager.

## What it does — every boot

1. Ensures `ufw` and `unattended-upgrades` are installed. `apt-get update` and package installation run **only** if either package is missing.
2. Enables automatic package-list updates and unattended security upgrades via `/etc/apt/apt.conf.d/52family-safety-auto-upgrades` plus `apt-daily.timer` and `apt-daily-upgrade.timer`.
3. Enables UFW with default **deny incoming** and **allow outgoing**. Existing explicit UFW rules are preserved; the script does not run `ufw reset`.
4. For active NetworkManager Wi-Fi and Ethernet profiles, sets CleanBrowsing Family DNS:
   - IPv4: `185.228.168.168`, `185.228.169.168`
   - IPv6: `2a0d:2a00:1::`, `2a0d:2a00:2::`
5. Creates `/etc/firefox/policies/policies.json` to disable and lock Firefox DNS-over-HTTPS, preventing Firefox from silently bypassing the configured DNS.

CleanBrowsing’s Family Filter blocks adult/explicit sites, malware/phishing, and proxy/VPN domains, and it enforces safe modes on Google, Bing, and YouTube. It is a useful filter, not a complete guarantee: a separate network, a VPN application, Tor, or a browser that does not honor the Firefox policy can bypass it.

## What it deliberately does not do

- It does **not** create, delete, or change user accounts or passwords.
- It does **not** block all VPN software or Tor clients at the operating-system level.
- It does **not** install browser extensions or lock Chrome/Chromium.
- It does **not** create backups or Timeshift snapshots.
- It does **not** reset existing firewall rules.
- It does **not** automatically reboot.

For meaningful protection, the child’s daily account must be a standard (non-administrator) account and the administrator password must remain private.

## Install

Copy this whole directory to the Mint PC, open a terminal inside it, then run:

```bash
chmod +x install.sh family-safety-enforce.sh uninstall.sh
sudo ./install.sh
```

The installer creates:

| Path | Purpose |
|---|---|
| `/usr/local/lib/family-safety/family-safety-enforce.sh` | Root-owned enforcement script |
| `/etc/systemd/system/family-safety-enforce.service` | Enabled one-shot systemd service that runs at every boot |
| `/etc/apt/apt.conf.d/52family-safety-auto-upgrades` | Automatic update configuration |
| `/etc/firefox/policies/policies.json` | Locks Firefox DNS-over-HTTPS off |

It enables no listening network service and opens no firewall ports.

## Verify on the Mint PC

```bash
systemctl status family-safety-enforce.service --no-pager
nmcli -t -f UUID,IP4.DNS,IP6.DNS connection show
sudo ufw status verbose
cat /etc/firefox/policies/policies.json
```

In Firefox, open `about:policies`: the `DNSOverHTTPS` policy should appear under **Active**. Restart Firefox after installation if it was already open.

For a boot test:

```bash
sudo reboot
# After login:
systemctl is-enabled family-safety-enforce.service
systemctl is-active family-safety-enforce.service
journalctl -u family-safety-enforce.service -b --no-pager
```

A oneshot service can become `inactive (dead)` after completing successfully unless `RemainAfterExit=yes` is set. This bundle leaves that default intact; use the journal and exit code to confirm a completed run.

## Remove service artifacts

```bash
sudo ./uninstall.sh
```

Removal stops and deletes only the installed systemd unit, enforcement script, and Firefox policy. It intentionally leaves firewall configuration, automated-update configuration, installed packages, and DNS settings intact, so removal does not weaken an otherwise working system unexpectedly. Restore DNS through Mint Network Settings (or `nmcli`) when you intentionally want to stop using the filter.

## Sources

- CleanBrowsing Family DNS: https://cleanbrowsing.org/ip-address
- Firefox policy location and DNS-over-HTTPS policy: https://mozilla.github.io/policy-templates/
- UFW defaults / enablement: https://manpages.ubuntu.com/manpages/noble/man8/ufw.8.html
