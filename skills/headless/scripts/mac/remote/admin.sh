#!/bin/bash
# remote/admin.sh - the admin session's part on the Mac, run as root by
# admin.sh with sudo -S. Standard input holds the login's password (one
# line) after the line sudo read. settings.json sits beside this file.
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

PASSWORD=""
IFS= read -r PASSWORD || true
exec < /dev/null
[ -n "$PASSWORD" ] || die "no password on standard input"

if [ "$auto_login" = true ] && [ "$(fdesetup isactive 2> /dev/null || true)" = true ]; then
  die "FileVault is on, and macOS cannot sign in by itself past FileVault's unlock screen. Turn FileVault off in System Settings, or set autoLogin to false in settings.json, then run this again"
fi

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
