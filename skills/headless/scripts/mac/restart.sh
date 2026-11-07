#!/bin/bash
# restart.sh - restart the Mac and wait until it is back: SSH by key again,
# a new boot time, and, when automatic sign-in is on, the user signed in on
# the screen. The password comes from the store for sudo -S.
#
# usage: restart.sh DIR [--timeout SECONDS]
# shellcheck source=skills/headless/scripts/mac/lib.sh
. "$(dirname "$0")/lib.sh"
load_config "${1-}"
TIMEOUT=900
[ "${2-}" != --timeout ] || TIMEOUT="${3:?--timeout needs seconds}"
need_key
with_secrets "$@"
read_password

boot() { on 'sysctl -n kern.boottime' 2> /dev/null | sed -n 's/.*sec = \([0-9]*\),.*/\1/p'; }
before="$(boot)"
[ -n "$before" ] || die "could not read the boot time"
say "restarting $ADDRESS"
# Detached, so the session ends cleanly before the Mac goes down.
as_root "/bin/sh -c '(sleep 2; /sbin/shutdown -r now) > /dev/null 2>&1 &'" > /dev/null || die "sudo refused the restart"
unset PASSWORD

start=$SECONDS
after=""
while [ $((SECONDS - start)) -lt "$TIMEOUT" ]; do
  sleep 10
  after="$(boot || true)"
  [ -n "$after" ] && [ "$after" != "$before" ] && break
done
[ -n "$after" ] && [ "$after" != "$before" ] || die "$ADDRESS did not come back within $TIMEOUT seconds"
say "back after $((SECONDS - start)) seconds (new boot time $after)"

if on 'plutil -extract autoLogin raw /etc/headless/settings.json' 2> /dev/null | grep -qx true; then
  start=$SECONDS
  console=""
  while [ $((SECONDS - start)) -lt 300 ]; do
    console="$(on 'stat -f %Su /dev/console' 2> /dev/null || true)"
    [ "$console" = "$LOGIN" ] && break
    sleep 5
  done
  [ "$console" = "$LOGIN" ] || die "$LOGIN is not signed in on the screen after the restart (console: ${console:-unknown}); automatic sign-in did not work"
  say "$LOGIN signed in on the screen by itself"
fi
