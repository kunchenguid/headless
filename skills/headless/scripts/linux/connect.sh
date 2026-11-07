#!/bin/bash
# connect.sh - the first sign-in to a Linux machine: pin its host key in the
# config folder, sign in once with the password from the store, add your
# public key to the admin account, and check that key sign-in works. Then
# say which way the machine is set up from here.
#
# usage: connect.sh DIR
#
# It is safe to run again: a pinned host key must still match, and a key
# that already works needs no password at all.
# shellcheck source=skills/headless/scripts/linux/lib.sh
. "$(dirname "$0")/lib.sh"
load_config "${1-}"
FIRST_SIGN_IN_ARGS=("$@")
first_sign_in "is the SSH server on and reachable?"

facts="$(on '. /etc/os-release; printf "%s|%s|%s|%s\n" "$(uname -s)" "$(uname -m)" "$ID" "$PRETTY_NAME"; id -Gn')"
IFS='|' read -r os arch id pretty <<< "$(printf '%s\n' "$facts" | head -n 1)"
[ "$os" = Linux ] || die "$ADDRESS is not Linux ($os); use the skill's part for that system"
printf '%s\n' "$facts" | tail -n 1 | tr ' ' '\n' | grep -qxE 'wheel|sudo' \
  || die "$LOGIN is in neither the wheel nor the sudo group on $ADDRESS, so it cannot be its administrator"
case "$id" in
  nixos)
    say "$ADDRESS runs $pretty on $arch, and $LOGIN is an administrator"
    say "next: apply.sh sets it up with the headless NixOS module" ;;
  *)
    say "$ADDRESS runs $pretty on $arch (not NixOS), and $LOGIN is an administrator"
    say "next, the user's choice: install-nixos.sh replaces the system with NixOS and erases the disk, or apply.sh keeps $pretty and applies the distro-neutral script" ;;
esac
