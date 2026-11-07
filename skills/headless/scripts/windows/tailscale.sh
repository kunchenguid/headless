#!/bin/bash
# tailscale.sh - join the Windows machine's Tailscale to your tailnet. Turn
# it on first: "tailscale": { "enable": true } in settings.json, then
# apply.sh (which installs Tailscale in unattended mode).
#
# usage: tailscale.sh DIR          join, with the auth key when headless.env
#                                  names TAILSCALE_KEY_REF, otherwise print a
#                                  sign-in link for you to open
#        tailscale.sh DIR --wait   wait (up to 10 minutes) until the machine
#                                  is connected, after you opened the link
#
# TAILSCALE_LOGIN_SERVER in headless.env picks a control server other than
# Tailscale's own (such as Headscale). No admin password is needed: an
# administrator's key sign-in may run Tailscale on Windows.
# shellcheck source=skills/headless/scripts/windows/lib.sh
. "$(dirname "$0")/lib.sh"
load_config "${1-}"
need_key
copy_remote
ts_state() { run_remote tailscale -Mode state < /dev/null 2> /dev/null | tr -d '\r' | tail -n 1; }
state="$(ts_state)"
[ "$state" != off ] || die "Tailscale is off on $ADDRESS; set \"tailscale\": { \"enable\": true } in settings.json and run apply.sh"

if [ "${2-}" = --wait ]; then
  start=$SECONDS
  while [ $((SECONDS - start)) -lt 600 ]; do
    state="$(ts_state)"
    [ "${state%% *}" = Running ] && { say "Tailscale connected: ${state#* }"; exit 0; }
    sleep 5
  done
  die "Tailscale is not connected after 10 minutes; run tailscale.sh again for a fresh link"
fi
if [ "${state%% *}" = Running ]; then
  say "Tailscale already connected: ${state#* }"
  exit 0
fi

server="${TAILSCALE_LOGIN_SERVER:--}"
if [ -n "$TAILSCALE_KEY_REF" ]; then
  # The auth key comes from the store on descriptor 4, straight to the machine.
  if [ "${HEADLESS_SECRETS_WIRED-}" != 1 ]; then
    export HEADLESS_SECRETS_WIRED=1
    exec "$SCRIPTS/secret-run.sh" --fd 4 "$TAILSCALE_KEY_REF" -- "$0" "$@"
  fi
  KEY=""
  IFS= read -r KEY <&4 || true
  exec 4<&-
  [ -n "$KEY" ] || die "the store gave no Tailscale auth key for $TAILSCALE_KEY_REF"
  printf '%s\n' "$KEY" | run_remote tailscale -Mode key -Server "$server" || die "Tailscale did not join with the auth key"
  unset KEY
  state="$(ts_state)"
  [ "${state%% *}" = Running ] || die "Tailscale did not connect"
  say "Tailscale connected: ${state#* }"
else
  run_remote tailscale -Mode link -Server "$server" < /dev/null | tr -d '\r' || die "Tailscale gave no sign-in link"
  say "open the link above and approve the machine, then run: tailscale.sh $CONFIG --wait"
fi
