#!/bin/bash
# connect.sh - the first sign-in: pin the Mac's host key in the config
# folder, sign in once with the password from the store, add your public key
# to the admin account, and check that key sign-in works.
#
# usage: connect.sh DIR
#
# It is safe to run again: a pinned host key must still match, and a key
# that already works needs no password at all.
# shellcheck source=skills/headless/scripts/mac/lib.sh
. "$(dirname "$0")/lib.sh"
load_config "${1-}"
FIRST_SIGN_IN_ARGS=("$@")
first_sign_in "is Remote Login on?"

facts="$(on 'printf "%s %s %s\n" "$(uname -s)" "$(uname -m)" "$(sw_vers -productVersion)"; id -Gn')"
read -r os arch version <<< "$(printf '%s\n' "$facts" | head -n 1)"
[ "$os" = Darwin ] || die "$ADDRESS is not a Mac ($os); this part of the skill is for macOS"
[ "$arch" = arm64 ] || die "$ADDRESS is an $arch Mac; the skill supports Apple silicon only"
printf '%s\n' "$facts" | tail -n 1 | tr ' ' '\n' | grep -qx admin || die "$LOGIN is not an administrator on $ADDRESS"
say "$ADDRESS is macOS $version on Apple silicon and $LOGIN is an administrator"
