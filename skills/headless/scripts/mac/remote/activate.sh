#!/bin/bash
# remote/activate.sh - switch the Mac to a built nix-darwin system, run as
# root by apply.sh with sudo -S.
#
# usage: sudo -S bash activate.sh SYSTEM
set -euo pipefail
die() { echo "headless: $*" >&2; exit 1; }
exec < /dev/null
SYSTEM="${1:?usage: activate.sh SYSTEM}"
[ "$(id -u)" -eq 0 ] || die "run activate.sh as root"
[[ "$SYSTEM" =~ ^/nix/store/[a-z0-9]{32}-darwin-system-[A-Za-z0-9._-]+$ ]] && [ -x "$SYSTEM/activate" ] \
  || die "$SYSTEM is not a built nix-darwin system"
export HOME=/var/root

# nix-darwin refuses to replace an /etc file it did not write and does not
# recognize. Before the first switch, move each such file aside; nix-darwin
# owns them afterwards, so later switches move nothing.
if [ ! -e /run/current-system ]; then
  while IFS= read -r f; do
    if [ -f "/etc/$f" ] && [ ! -L "/etc/$f" ]; then
      mv "/etc/$f" "/etc/$f.before-nix-darwin"
      echo "headless: moved /etc/$f aside to /etc/$f.before-nix-darwin"
    fi
  done < <(cd "$SYSTEM/etc" && find . \( -type l -o -type f \) | sed 's|^\./||' | sort)
fi

profile=/nix/var/nix/profiles/system
/nix/var/nix/profiles/default/bin/nix-env -p "$profile" --set "$SYSTEM"
if ! "$SYSTEM/activate"; then
  # Leave the profile on the system that is actually active.
  if [ -e /run/current-system ]; then
    /nix/var/nix/profiles/default/bin/nix-env -p "$profile" --rollback > /dev/null 2>&1 || true
  fi
  die "activation failed; the Mac stays on its previous system"
fi
