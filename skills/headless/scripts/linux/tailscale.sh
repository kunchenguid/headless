#!/bin/bash
# tailscale.sh - join the Linux machine's Tailscale daemon to your tailnet.
# Turn it on first: "tailscale": { "enable": true } in settings.json, then
# apply.sh.
#
# usage: tailscale.sh DIR          join, with the auth key when headless.env
#                                  names TAILSCALE_KEY_REF, otherwise print a
#                                  sign-in link for you to open
#        tailscale.sh DIR --wait   wait (up to 10 minutes) until the machine
#                                  is connected, after you opened the link
#
# TAILSCALE_LOGIN_SERVER in headless.env picks a control server other than
# Tailscale's own (such as Headscale).
# shellcheck source=skills/headless/scripts/linux/lib.sh
. "$(dirname "$0")/lib.sh"
load_config "${1-}"
need_key
on 'grep -qx TAILSCALE=true /etc/headless/settings.env' 2> /dev/null \
  || die "Tailscale is off on $ADDRESS; set \"tailscale\": { \"enable\": true } in settings.json and run apply.sh"

# shellcheck disable=SC2016 # runs on the machine
state() { on 'tailscale status --json 2> /dev/null | sed -n "s/^[[:space:]]*\"BackendState\":[[:space:]]*\"\([A-Za-z]*\)\".*/\1/p" | head -n 1' || true; }
ip4() { on 'tailscale ip -4' | head -n 1; }

if [ "${2-}" = --wait ]; then
  start=$SECONDS
  while [ $((SECONDS - start)) -lt 600 ]; do
    [ "$(state)" = Running ] && { say "Tailscale connected: $(ip4)"; exit 0; }
    sleep 5
  done
  die "Tailscale is not connected after 10 minutes; run tailscale.sh again for a fresh link"
fi

if [ "$(state)" = Running ]; then
  say "Tailscale already connected: $(ip4)"
  exit 0
fi

NEED_TAILSCALE_KEY=1 with_secrets "$@"
read_password
host="$(on 'h="$(sed -n "s/^HOST_NAME=//p" /etc/headless/settings.env)"; [ -n "$h" ] || h="$(hostname)"; printf "%s" "$h"')"
copy_remote
server="${TAILSCALE_LOGIN_SERVER:--}"
if [ -n "$TAILSCALE_KEY_REF" ]; then
  KEY=""
  IFS= read -r KEY <&4 || true
  exec 4<&-
  [ -n "$KEY" ] || die "the store gave no Tailscale auth key for $TAILSCALE_KEY_REF"
  EXTRA_STDIN="$KEY" as_root "/usr/bin/env bash ~/.headless/remote/tailscale.sh key $host $server" || die "Tailscale did not join with the auth key"
  unset KEY PASSWORD
  [ "$(state)" = Running ] || die "Tailscale did not connect"
  say "Tailscale connected: $(ip4)"
else
  as_root "/usr/bin/env bash ~/.headless/remote/tailscale.sh link $host $server" || die "Tailscale gave no sign-in link"
  unset PASSWORD
  say "open the link above and approve the machine, then run: tailscale.sh $CONFIG --wait"
fi
