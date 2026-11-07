#!/bin/bash
# restart.sh - restart the Linux machine and wait until it is back: SSH by
# key again with a new boot id, and, when automatic sign-in is on, the
# user's session running without anyone signing in. The password comes from
# the store for sudo -S.
#
# usage: restart.sh DIR [--timeout SECONDS]
# shellcheck source=skills/headless/scripts/linux/lib.sh
. "$(dirname "$0")/lib.sh"
load_config "${1-}"
TIMEOUT=900
[ "${2-}" != --timeout ] || TIMEOUT="${3:?--timeout needs seconds}"
need_key
with_secrets "$@"
read_password

# boot: the boot id, then when the user's session (user@UID.service) and
# this SSH sign-in started, in microseconds since boot. The first sign-in
# after the restart tells whether the session started by itself before it.
# shellcheck disable=SC2016 # runs on the machine
boot() {
  on 'printf "%s %s %s\n" "$(cat /proc/sys/kernel/random/boot_id)" \
    "$(systemctl show -p ActiveEnterTimestampMonotonic --value "user@$(id -u).service" 2> /dev/null)" \
    "$(loginctl show-session "${XDG_SESSION_ID:-none}" -p TimestampMonotonic --value 2> /dev/null)"' 2> /dev/null
}
read -r before _ <<< "$(boot)"
[ -n "$before" ] || die "could not read the boot id"
say "restarting $ADDRESS"
# Detached, so the session ends cleanly before the machine goes down.
as_root "/bin/sh -c '(sleep 2; systemctl reboot) > /dev/null 2>&1 &'" > /dev/null || die "sudo refused the restart"
unset PASSWORD

start=$SECONDS
after=""
while [ $((SECONDS - start)) -lt "$TIMEOUT" ]; do
  sleep 10
  read -r after started signed_in <<< "$(boot || true)"
  [ -n "$after" ] && [ "$after" != "$before" ] && break
done
[ -n "$after" ] && [ "$after" != "$before" ] || die "$ADDRESS did not come back within $TIMEOUT seconds"
say "back after $((SECONDS - start)) seconds (new boot id $after)"

if on 'grep -qx AUTO_LOGIN=true /etc/headless/settings.env' 2> /dev/null; then
  # Signing in over SSH starts the session too, so it must have started
  # before that first sign-in.
  [[ "${started-}" =~ ^[0-9]+$ ]] && [ "$started" -gt 0 ] && [[ "${signed_in-}" =~ ^[0-9]+$ ]] \
    || die "could not read when $LOGIN's session started"
  [ "$started" -lt "$signed_in" ] \
    || die "$LOGIN's session did not start by itself after the restart; it started with the first SSH sign-in"
  say "$LOGIN's session started by itself, $((started / 1000000)) seconds after boot and before anyone signed in"
fi
