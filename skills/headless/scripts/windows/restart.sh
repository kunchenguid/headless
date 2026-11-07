#!/bin/bash
# restart.sh - restart the Windows machine and wait until it is back: SSH by
# key again with a new boot time, and, when automatic sign-in is on, the
# account signed in on the machine's own screen without anyone signing in.
# An administrator's key sign-in may restart Windows, so no password is
# needed.
#
# usage: restart.sh DIR [--timeout SECONDS]
# shellcheck source=skills/headless/scripts/windows/lib.sh
. "$(dirname "$0")/lib.sh"
load_config "${1-}"
TIMEOUT=900
[ "${2-}" != --timeout ] || TIMEOUT="${3:?--timeout needs seconds}"
need_key

# boot: when Windows started, in seconds since 1970.
# shellcheck disable=SC2016 # runs on the machine
boot() {
  win_ps '[long]((Get-CimInstance Win32_OperatingSystem).LastBootUpTime.ToUniversalTime() - [datetime]"1970-01-01").TotalSeconds' \
    < /dev/null 2> /dev/null | tr -d '\r' | grep -E '^[0-9]+$' || true
}
before="$(boot)"
[ -n "$before" ] || die "could not read when $ADDRESS started"
say "restarting $ADDRESS"
win_ps 'shutdown.exe /r /t 3 /f /d p:4:1; exit $LASTEXITCODE' < /dev/null > /dev/null || die "Windows refused the restart"

start=$SECONDS
after=""
while [ $((SECONDS - start)) -lt "$TIMEOUT" ]; do
  sleep 10
  after="$(boot)"
  [ -n "$after" ] && [ "$after" != "$before" ] && break
done
[ -n "$after" ] && [ "$after" != "$before" ] || die "$ADDRESS did not come back within $TIMEOUT seconds"
say "back after $((SECONDS - start)) seconds (started again at $(date -u -r "$after" '+%H:%M:%S' 2> /dev/null || date -u -d "@$after" '+%H:%M:%S') UTC)"

if [ "$(win_ps '(Get-Content -Raw (Join-Path $env:ProgramData "headless\settings.json") | ConvertFrom-Json).autoLogin' < /dev/null 2> /dev/null | tr -d '\r')" = True ]; then
  # The account's processes in a session of the screen (SSH sessions run in
  # session 0): only a sign-in at the machine, or automatic sign-in, starts
  # them. Windows signs in a little after it starts; wait up to 5 minutes.
  # shellcheck disable=SC2016 # runs on the machine
  probe='$b = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
$p = Get-Process -IncludeUserName -ErrorAction SilentlyContinue | Where-Object { $_.SessionId -gt 0 -and $_.UserName -and ($_.UserName -split "\\")[-1] -eq "'"$LOGIN"'" } | Sort-Object StartTime | Select-Object -First 1
if ($p) { "{0} {1}" -f $p.SessionId, [long]($p.StartTime - $b).TotalSeconds }'
  signed_in=""
  while [ $((SECONDS - start)) -lt $((TIMEOUT + 300)) ]; do
    signed_in="$(win_ps "$probe" < /dev/null 2> /dev/null | tr -d '\r' | grep -E '^[0-9]+ -?[0-9]+$' || true)"
    [ -n "$signed_in" ] && break
    sleep 10
  done
  [ -n "$signed_in" ] || die "$LOGIN did not sign in by itself on $ADDRESS's screen after the restart; check the password in the store and run apply.sh again"
  say "$LOGIN signed in by itself on the machine's screen (session ${signed_in% *}), ${signed_in#* } seconds after start-up"
fi
