#!/bin/bash
# new-config.sh - make a Windows machine's config folder on this computer,
# or update the settings of one.
#
# usage: new-config.sh DIR --address ADDRESS --login LOGIN --password-ref REF
#          [--ssh-key PATH] [--host-name NAME] [--no-auto-login]
#          [--tailscale] [--tailscale-key-ref REF] [--tailscale-login-server URL]
#          [--extra-off NAME]... [--keep-password-ssh]
#
# DIR becomes a git folder holding settings.json (the headless settings),
# headless.env (how to reach the machine and where the password lives; no
# secret) and machine.ps1 (your own additions, run after the headless
# settings on every apply; an existing one is kept). settings.json and
# headless.env are written again from the options given.
#
# Extras, each on unless named with --extra-off: neverSleep,
# powerButtonShutsDown, hideSleep, updatesOvernight. A Windows host name is
# at most 15 characters.
# shellcheck source=skills/headless/scripts/windows/lib.sh
. "$(dirname "$0")/lib.sh"
EXTRAS=(neverSleep powerButtonShutsDown hideSleep updatesOvernight)
TEMPLATE="$SCRIPTS/../assets/windows"
TEMPLATE_FILES=machine.ps1
for a in "$@"; do
  [[ "$a" != --host-name ]] || { h=1; continue; }
  [ "${h-}" != 1 ] || { [ "${#a}" -le 15 ] || die "--host-name must be at most 15 characters on Windows"; h=0; }
done
new_config "$@"
