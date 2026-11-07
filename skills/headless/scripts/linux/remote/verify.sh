#!/bin/bash
# remote/verify.sh - compare the Linux machine with /etc/headless/settings.env
# (written by the NixOS module or the distro-neutral script), as the login,
# without root. One "ok" or "FAIL" line per setting.
set -uo pipefail
S=/etc/headless/settings.env
ok() { echo "ok    $1"; }
fail() { echo "FAIL  $1"; }
na() { echo "n/a   $1"; }
is() { if [ "$1" = "$2" ]; then ok "$3"; else fail "$3 (found '$1', want '$2')"; fi; }
get() { sed -n "s/^$1=//p" "$S" | head -n 1; }

if [ ! -f "$S" ]; then fail "headless settings applied (no $S; run apply.sh)"; exit 0; fi
kind="$(get KIND)"
if [ "$kind" = nixos ]; then
  v="$(/run/current-system/sw/bin/nix --version 2> /dev/null)" && ok "Nix: $v" || fail "Nix installed"
  is "$(readlink -f /run/current-system)" "$(readlink -f /nix/var/nix/profiles/system)" "NixOS runs the system it boots ($(readlink /run/current-system))"
else
  # shellcheck source=/dev/null
  . /etc/os-release
  ok "distro-neutral script applied on $PRETTY_NAME"
fi

user="$(get USER_NAME)"
is "$(id -un)" "$user" "signed in as the configured user"
host="$(get HOST_NAME)"
[ -z "$host" ] || is "$(hostname)" "$host" "host name"

if [ "$(get KEY_ONLY)" = true ]; then
  if [ "$kind" = nixos ]; then
    f=/etc/ssh/sshd_config
  else
    f=/etc/ssh/sshd_config.d/00-headless.conf
  fi
  if [ ! -r "$f" ]; then
    na "sshd key-only setting in $f (only root can read it; the password sign-in check covers it)"
  elif grep -qx 'PasswordAuthentication no' "$f"; then
    ok "sshd key-only setting in $f"
  else
    fail "sshd key-only setting in $f"
  fi
fi

if sudo -n true 2> /dev/null; then fail "sudo asks for the password (a passwordless rule exists)"; else ok "sudo asks for the password"; fi

uid="$(id -u)"
if [ "$(get AUTO_LOGIN)" = true ]; then
  [ -e "/var/lib/systemd/linger/$user" ] && ok "$user's session starts at boot (lingering)" || fail "$user's session starts at boot (lingering)"
  is "$(systemctl is-active "user@$uid.service" 2> /dev/null)" active "$user's session is running"
else
  [ ! -e "/var/lib/systemd/linger/$user" ] && ok "$user's session does not start at boot" || fail "$user's session does not start at boot"
fi

if [ "$(get NEVER_SLEEP)" = true ]; then
  for t in sleep.target suspend.target hibernate.target hybrid-sleep.target; do
    is "$(systemctl is-enabled "$t" 2> /dev/null)" masked "$t masked (never sleeps)"
  done
fi

if [ "$(get AUTO_UPDATES)" = true ]; then
  case "$kind:$(get PACKAGES)" in
    nixos:*) na "automatic updates (on NixOS, update flake.lock in the config folder and apply)" ;;
    script:apt)
      [[ "$(dpkg-query -W -f='${Status}' unattended-upgrades 2> /dev/null)" == *'install ok installed'* ]] \
        && ok "unattended-upgrades installed" || fail "unattended-upgrades installed"
      # (grep -q would stop reading early, and pipefail would count that.)
      apt-config dump 2> /dev/null | grep -cx 'APT::Periodic::Unattended-Upgrade "1";' > /dev/null \
        && ok "unattended upgrades turned on" || fail "unattended upgrades turned on"
      is "$(systemctl is-enabled apt-daily-upgrade.timer 2> /dev/null)" enabled "apt-daily-upgrade.timer on" ;;
    script:dnf5)
      rpm -q dnf5-plugin-automatic > /dev/null 2>&1 && ok "dnf5-plugin-automatic installed" || fail "dnf5-plugin-automatic installed"
      grep -qx 'apply_updates = yes' /etc/dnf/automatic.conf 2> /dev/null && ok "dnf5 automatic applies updates" || fail "dnf5 automatic applies updates"
      is "$(systemctl is-enabled dnf5-automatic.timer 2> /dev/null)" enabled "dnf5-automatic.timer on" ;;
    *) fail "automatic updates (no supported package manager)" ;;
  esac
fi

if [ "$(get TAILSCALE)" = true ]; then
  st="$(tailscale status --json 2> /dev/null | sed -n 's/^[[:space:]]*"BackendState":[[:space:]]*"\([A-Za-z]*\)".*/\1/p' | head -n 1)"
  is "$st" Running "Tailscale connected"
fi
exit 0
