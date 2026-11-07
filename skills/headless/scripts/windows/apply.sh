#!/bin/bash
# apply.sh - make the Windows machine what its config folder says: key-only
# SSH with PowerShell as the SSH shell, automatic sign-in, the extras, and
# Tailscale if chosen (settings.json), then the folder's own machine.ps1.
# It changes only what differs and prints one "headless: changed:" line per
# change; run again unchanged, it prints none.
#
# usage: apply.sh DIR
#
# An administrator's SSH session on Windows already has full rights, so no
# password is needed for that. With automatic sign-in on, the password comes
# from the store each time, for Windows to sign the account in at start-up;
# it reaches the machine on standard input only.
# shellcheck source=skills/headless/scripts/windows/lib.sh
. "$(dirname "$0")/lib.sh"
load_config "${1-}"
[ $# -le 1 ] || die "unknown option $2"
need_key
auto="$(setting_on autoLogin true)"
if [ "$auto" = true ]; then
  with_secrets "$CONFIG"
  read_password
fi

say "copying $CONFIG to $ADDRESS"
copy_config
say "applying settings.json on $ADDRESS"
if [ "$auto" = true ]; then
  printf '%s\n' "$PASSWORD" | run_remote apply -Login "$LOGIN" || die "apply stopped; the lines above say where"
  unset PASSWORD
else
  run_remote apply -Login "$LOGIN" < /dev/null || die "apply stopped; the lines above say where"
fi

# The folder's own additions, after the headless settings.
if [ -f "$CONFIG/machine.ps1" ]; then
  say "running machine.ps1 on $ADDRESS"
  on "$POWERSHELL -File $WIN_HOME/config/machine.ps1" < /dev/null || die "machine.ps1 stopped; the lines above say where"
fi
if command -v git > /dev/null && [ -d "$CONFIG/.git" ]; then git -C "$CONFIG" add -A; fi
say "applied"
