#!/bin/bash
# connect.sh - the first sign-in to a Windows machine: pin its host key in
# the config folder, sign in once with the password from the store, add your
# public key for the administrator account, and check that key sign-in
# works. Then say what the machine runs.
#
# usage: connect.sh DIR
#
# It is safe to run again: a pinned host key must still match, and a key
# that already works needs no password at all.
# shellcheck source=skills/headless/scripts/windows/lib.sh
. "$(dirname "$0")/lib.sh"
load_config "${1-}"
FIRST_SIGN_IN_ARGS=("$@")
first_sign_in "is OpenSSH Server installed and running, and is the network Private so the firewall lets SSH in (step W1)?"

# shellcheck disable=SC2016 # runs on the machine
facts="$(win_ps '
$os = Get-CimInstance Win32_OperatingSystem
$cv = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion"
$p = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
$admin = $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$local = [bool](Get-LocalUser -Name $env:USERNAME -ErrorAction SilentlyContinue)
"{0}|{1}|{2}|{3}|{4}|{5}" -f "windows", $os.Caption, $cv.DisplayVersion, $os.BuildNumber, $env:PROCESSOR_ARCHITECTURE, ("" + $admin + "," + $local)
' 2> /dev/null | tr -d '\r' | grep '^windows|' || true)"
[ -n "$facts" ] || die "$ADDRESS does not answer like Windows; use the skill's part for its system"
IFS='|' read -r _ caption release build arch flags <<< "$facts"
[ "${flags%,*}" = True ] || die "$LOGIN on $ADDRESS has no administrator rights in its SSH session; the skill needs an administrator account"
[ "${flags#*,}" = True ] \
  || say "$LOGIN is not a local account on $ADDRESS (a Microsoft or domain account); automatic sign-in needs that account's own password in the store"
say "$ADDRESS runs $caption ${release:+$release }(build $build) on $arch, and $LOGIN is an administrator"
say "next: apply.sh applies the settings in settings.json"
