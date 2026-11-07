#!/bin/bash
# remote/verify.sh - compare the Mac with /etc/headless/settings.json, as
# the login, without root. One "ok" or "FAIL" line per setting.
set -uo pipefail
S=/etc/headless/settings.json
ok() { echo "ok    $1"; }
fail() { echo "FAIL  $1"; }
is() { if [ "$1" = "$2" ]; then ok "$3"; else fail "$3 (found '$1', want '$2')"; fi; }
get() { plutil -extract "$1" raw "$S" 2> /dev/null; }

if [ ! -f "$S" ]; then fail "headless system active (no $S; run apply.sh)"; exit 0; fi
v="$(/nix/var/nix/profiles/default/bin/nix --version 2> /dev/null)" && ok "Nix: $v" || fail "Nix installed"
[ -e /run/current-system ] && ok "nix-darwin system: $(readlink /run/current-system)" || fail "nix-darwin system active"

user="$(get user)"
is "$(id -un)" "$user" "signed in as the configured user"
host="$(get hostName)"
[ -z "$host" ] || is "$(scutil --get LocalHostName 2> /dev/null)" "$host" "host name"

if [ "$(get keyOnlySsh)" = true ]; then
  grep -qx 'PasswordAuthentication no' /etc/ssh/sshd_config.d/000-headless.conf 2> /dev/null \
    && ok "sshd key-only drop-in" || fail "sshd key-only drop-in"
fi

if sudo -n true 2> /dev/null; then fail "sudo asks for the password (a passwordless rule exists)"; else ok "sudo asks for the password"; fi

fv="$(fdesetup isactive 2> /dev/null || true)"
if [ "$(get autoLogin)" = true ]; then
  is "$(defaults read /Library/Preferences/com.apple.loginwindow autoLoginUser 2> /dev/null)" "$user" "automatic sign-in user"
  [ -e /etc/kcpassword ] && ok "automatic sign-in password stored" || fail "automatic sign-in password stored (run admin.sh)"
  [ "$(stat -f '%Su %Lp' /etc/kcpassword 2> /dev/null)" = "root 600" ] && ok "automatic sign-in password root-only" || fail "automatic sign-in password root-only"
  is "$fv" false "FileVault off (needed for automatic sign-in)"
else
  [ ! -e /etc/kcpassword ] && ok "no automatic sign-in password stored" || fail "no automatic sign-in password stored"
fi

pm="$(pmset -g)"
pmv() { printf '%s\n' "$pm" | awk -v k="$1" '$1 == k { print $2; exit }'; }
if [ "$(get extras.neverSleep)" = true ]; then
  is "$(pmv sleep)" 0 "machine never sleeps"
  is "$(pmv disksleep)" 0 "disks never sleep"
fi
cap="$(pmset -g cap)"
has() { printf '%s\n' "$cap" | grep -qw "$1"; }
na() { echo "n/a   $1 (this Mac has no such power setting)"; }
if [ "$(get extras.startAfterPowerLoss)" = true ]; then
  if has autorestart; then is "$(pmv autorestart)" 1 "starts up after a power cut"; else na "start-up after power loss"; fi
fi
if [ "$(get extras.wakeOnLan)" = true ]; then
  if has womp; then is "$(pmv womp)" 1 "wake for network access"; else na "wake for network access"; fi
fi
[ "$(get extras.powerNapOff)" != true ] || is "$(pmv powernap)" 0 "Power Nap off"
if [ "$(get extras.spotlightOff)" = true ]; then
  mdutil -s / 2> /dev/null | grep -q 'Indexing disabled' && ok "Spotlight indexing off" || fail "Spotlight indexing off"
fi
[ "$(get extras.siriOff)" != true ] || is "$(defaults read com.apple.assistant.support 'Assistant Enabled' 2> /dev/null)" 0 "Siri off"

if [ "$(get tailscale)" = true ]; then
  ts=/run/current-system/sw/bin/tailscale
  st="$("$ts" status --json 2> /dev/null | plutil -extract BackendState raw - 2> /dev/null)"
  is "$st" Running "Tailscale connected"
fi
exit 0
