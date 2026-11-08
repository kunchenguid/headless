#!/bin/bash
# remote/admin.sh - the admin session's part on the Mac, run as root by
# admin.sh with sudo -S. Standard input holds the login's password (one
# line) after a --headless-stdin-- line. settings.json sits beside this file.
#
# usage: sudo -S bash admin.sh LOGIN
set -euo pipefail
die() { echo "headless: $*" >&2; exit 1; }
say() { echo "headless: $*"; }

LOGIN="${1:?usage: admin.sh LOGIN}"
HERE="$(cd "$(dirname "$0")" && pwd)"
# Determinate Nix's installer for Apple silicon, pinned by version and hash.
NIX_INSTALLER_URL=https://github.com/DeterminateSystems/nix-installer/releases/download/v3.24.1/nix-installer-aarch64-darwin
NIX_INSTALLER_SHA256=34199f983d1a08e76a4fb33b28691faa637fc4a8677b4de20bd951126e1bdada
NIX=/nix/var/nix/profiles/default/bin/nix

[ "$(id -u)" -eq 0 ] || die "run admin.sh as root"
# sudo keeps the login's HOME; root works in its own, so nothing in the
# login's home becomes root's.
export HOME=/var/root
[[ "$LOGIN" =~ ^[a-z_][a-z0-9_-]*$ ]] || die "LOGIN is not a plain account name"
dscl . -read "/Users/$LOGIN" UniqueID > /dev/null 2>&1 || die "$LOGIN is not an account on this Mac"
auto_login="$(plutil -extract autoLogin raw "$HERE/settings.json")"

# Skip to the mark line (the line sudo read, if it needed one, comes first).
PASSWORD=""
while IFS= read -r line && [ "$line" != --headless-stdin-- ]; do :; done
IFS= read -r PASSWORD || true
exec < /dev/null
[ -n "$PASSWORD" ] || die "no password on standard input"

# Automatic sign-in cannot get past FileVault's unlock screen, so with it
# chosen this turns FileVault off with the login's password, and asks the
# user only when macOS refuses. fdesetup reports most refusals with exit 0,
# so its status afterwards is what counts.
fv_status() { fdesetup status 2> /dev/null || true; }
fv_ask() {
  die "ask the user: $1, or set autoLogin to false in settings.json, then run admin.sh again"
}
fv_wait() { # fv_wait TEXT SECONDS: wait while fdesetup status shows TEXT
  local start=$SECONDS
  while fv_status | grep -qF "$1"; do
    [ $((SECONDS - start)) -lt "$2" ] || die "FileVault still shows \"$1\" after $2 seconds; run admin.sh again later"
    sleep 5
  done
}
turn_filevault_off() {
  local esc out
  if fv_status | grep -qF "Encryption in progress"; then
    say "FileVault is still encrypting; waiting for it to finish first (macOS cannot turn it off before then)"
    fv_wait "Encryption in progress" 14400
  fi
  if ! fv_status | grep -qF "Decryption in progress"; then
    fdesetup list 2> /dev/null | cut -d, -f1 | grep -qxF "$LOGIN" \
      || fv_ask "$LOGIN cannot unlock FileVault on this Mac (it has no secure token), so its password cannot turn FileVault off. Turn FileVault off at the Mac (System Settings > Privacy & Security > FileVault) with an account that can"
    say "FileVault is on; turning it off with $LOGIN's password, so the Mac can sign in by itself"
    # The plist reaches fdesetup on standard input; printf is a shell
    # builtin, so the password is on no command line.
    esc="${PASSWORD//&/&amp;}"; esc="${esc//</&lt;}"; esc="${esc//>/&gt;}"
    out="$(printf '<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n<plist version="1.0"><dict><key>Username</key><string>%s</string><key>Password</key><string>%s</string></dict></plist>\n' "$LOGIN" "$esc" \
      | fdesetup disable -inputplist 2>&1 || true)"
    esc=""
    case "$out" in
      *"managed preferences"*)
        fv_ask "the organization that manages this Mac does not allow turning FileVault off (macOS said: $out). Ask whoever manages it to allow that" ;;
    esac
    fv_status | grep -qE "Decryption in progress|FileVault is Off" \
      || fv_ask "macOS did not turn FileVault off (it said: ${out:-nothing}). Turn FileVault off at the Mac (System Settings > Privacy & Security > FileVault)"
    say "FileVault turned off"
  fi
  # The disk decrypts in the background, and FileVault stays on until it
  # ends; a restart before then stops at its unlock screen.
  say "waiting for FileVault to finish decrypting (a restart before then stops at its unlock screen)"
  local start=$SECONDS
  fv_wait "Decryption in progress" 14400
  [ "$(fdesetup isactive 2> /dev/null || true)" = false ] \
    || fv_ask "FileVault is still on after decrypting ($(fv_status | head -n 1)). Turn FileVault off at the Mac (System Settings > Privacy & Security > FileVault)"
  say "FileVault is off (decryption took $((SECONDS - start)) seconds)"
}

if [ ! -x "$NIX" ]; then
  say "installing Determinate Nix..."
  installer="$(mktemp -t nix-installer)"
  curl -fsSL --retry 3 -o "$installer" "$NIX_INSTALLER_URL"
  echo "$NIX_INSTALLER_SHA256  $installer" | shasum -a 256 -c - > /dev/null || die "the Nix installer's hash does not match"
  chmod 0755 "$installer"
  "$installer" install --no-confirm
  rm -f "$installer"
fi
say "$("$NIX" --version)"

# This comes after the Nix install on purpose: right after FileVault
# decrypts, macOS could not mount a newly made encrypted volume (the Nix
# store's) until a restart.
if [ "$auto_login" = true ] && [ "$(fdesetup isactive 2> /dev/null || true)" = true ]; then
  turn_filevault_off
fi

if [ "$auto_login" = true ]; then
  # macOS keeps the automatic sign-in password as /etc/kcpassword: the
  # password XORed with Apple's fixed key, root-only. sysadminctl -autologin
  # would take the password on its command line, so this writes it from
  # standard input instead.
  printf '%s' "$PASSWORD" | /usr/bin/perl -e '
    local $/; my $pw = <STDIN>; length $pw or die "empty password\n";
    my @key = (0x7D, 0x89, 0x52, 0x23, 0xD2, 0xBC, 0xDD, 0xEA, 0xA3, 0xB9, 0x1F);
    my $n = (int(length($pw) / 12) + 1) * 12;
    my $out = "";
    for my $i (0 .. $n - 1) {
      my $c = $i < length($pw) ? ord(substr($pw, $i, 1)) : 0;
      $out .= chr($c ^ $key[$i % @key]);
    }
    umask 077;
    open(my $fh, ">", "/etc/kcpassword.new") or die "kcpassword: $!\n";
    binmode $fh; print $fh $out; close $fh or die "kcpassword: $!\n";
  '
  chown root:wheel /etc/kcpassword.new
  chmod 0600 /etc/kcpassword.new
  mv -f /etc/kcpassword.new /etc/kcpassword
  defaults write /Library/Preferences/com.apple.loginwindow autoLoginUser -string "$LOGIN"
  say "automatic sign-in stored for $LOGIN; it takes effect at the next start"
fi
unset PASSWORD
