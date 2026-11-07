#!/bin/sh
# remote/activate.sh - switch the NixOS machine to a built system and make
# it the boot default, run as root by apply.sh with sudo -S.
#
# usage: sudo -S sh activate.sh SYSTEM
set -eu
die() { echo "headless: $*" >&2; exit 1; }
exec < /dev/null
SYSTEM="${1:?usage: activate.sh SYSTEM}"
[ "$(id -u)" -eq 0 ] || die "run activate.sh as root"
case "$SYSTEM" in
  /nix/store/*-nixos-system-*) ;;
  *) die "$SYSTEM is not a built NixOS system" ;;
esac
[ -x "$SYSTEM/bin/switch-to-configuration" ] || die "$SYSTEM is not a built NixOS system"

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
