#!/bin/sh
# remote/activate.sh - switch the NixOS machine to a built system and make
# it the boot default, then keep the config it was built from in /etc/nixos,
# run as root by apply.sh with sudo -S.
#
# usage: sudo -S sh activate.sh SYSTEM CONFIG
set -eu
die() { echo "headless: $*" >&2; exit 1; }
exec < /dev/null
SYSTEM="${1:?usage: activate.sh SYSTEM CONFIG}" CONFIG="${2:?usage: activate.sh SYSTEM CONFIG}"
[ "$(id -u)" -eq 0 ] || die "run activate.sh as root"
case "$SYSTEM" in
  /nix/store/*-nixos-system-*) ;;
  *) die "$SYSTEM is not a built NixOS system" ;;
esac
[ -x "$SYSTEM/bin/switch-to-configuration" ] || die "$SYSTEM is not a built NixOS system"
[ -f "$CONFIG/flake.nix" ] || die "$CONFIG holds no flake.nix"

profile=/nix/var/nix/profiles/system
/run/current-system/sw/bin/nix-env -p "$profile" --set "$SYSTEM"
# A failed switch is usually one service that did not start: the new
# system is active and stays the boot default, and the lines above name the
# service. The previous system is one rollback away.
"$SYSTEM/bin/switch-to-configuration" switch \
  || die "the switch reported errors (above); fix them and apply again, or go back to the previous system with: sudo nixos-rebuild switch --rollback"
# NixOS writes a new host name to /etc/hostname, which the running system
# reads only at the next start; take it now.
name="$(cat /etc/hostname 2> /dev/null || true)"
if [ -n "$name" ] && [ "$(hostname)" != "$name" ]; then
  hostnamectl set-hostname --transient "$name"
fi

# The machine's own updates (system.autoUpgrade, or nixos-rebuild switch at
# the machine) build /etc/nixos: it gets this config, so they build the same
# system. What was there before is kept once, beside it.
mark=/etc/nixos/HEADLESS.md
if [ -e /etc/nixos ] && [ ! -e "$mark" ] && [ -n "$(ls -A /etc/nixos 2> /dev/null)" ]; then
  keep=/etc/nixos.before-headless
  [ ! -e "$keep" ] || keep="$keep.$(date +%Y%m%d%H%M%S)"
  mv /etc/nixos "$keep"
  echo "headless: kept the machine's own /etc/nixos in $keep"
fi
new="$(mktemp -d /etc/nixos.headless.XXXXXX)"
cp -R "$CONFIG/." "$new/"
cat > "$new/HEADLESS.md" <<'MD'
# Managed by the headless skill

This folder is a copy of the machine's config folder on your computer,
written by the skill's apply.sh each time it runs. `nixos-rebuild switch`
and `system.autoUpgrade` build it (`nixosConfigurations.machine`). Edit the
config folder and run apply.sh: changes made here are replaced at the next
apply. The machine's earlier /etc/nixos, if it had one, is in
/etc/nixos.before-headless.
MD
chown -R root:root "$new"
chmod -R u+rwX,go-w "$new"
chmod 0755 "$new"
rm -rf /etc/nixos
mv "$new" /etc/nixos
