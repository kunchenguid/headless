#!/bin/bash
# tailscale.sh - join the Mac's Tailscale daemon to your tailnet. Turn it on
# first: "tailscale": { "enable": true } in settings.json, then apply.sh.
#
# usage: tailscale.sh DIR          join, with the auth key when headless.env
#                                  names TAILSCALE_KEY_REF, otherwise print a
#                                  sign-in link for you to open
#        tailscale.sh DIR --wait   wait (up to 10 minutes) until the Mac is
#                                  connected, after you opened the link
#
# TAILSCALE_LOGIN_SERVER in headless.env picks a control server other than
# Tailscale's own (such as Headscale).
# shellcheck source=skills/headless/scripts/mac/lib.sh
. "$(dirname "$0")/lib.sh"
load_config "${1-}"
TS=/run/current-system/sw/bin/tailscale
need_key
on 'test ! -d /Applications/Tailscale.app' || die "the Tailscale app is already on $ADDRESS; leave it as it is and keep \"tailscale\" off in settings.json"
on 'plutil -extract tailscale raw /etc/headless/settings.json' 2> /dev/null | grep -qx true \
  || die "Tailscale is off in the Mac's system; set \"tailscale\": { \"enable\": true } in settings.json and run apply.sh"

state() { on "$TS status --json 2> /dev/null | plutil -extract BackendState raw - 2> /dev/null" || true; }

if [ "${2-}" = --wait ]; then
  start=$SECONDS
  while [ $((SECONDS - start)) -lt 600 ]; do
    [ "$(state)" = Running ] && { say "Tailscale connected: $(on "$TS ip -4" | head -n 1)"; exit 0; }
    sleep 5
  done
  die "Tailscale is not connected after 10 minutes; run tailscale.sh again for a fresh link"
fi

if [ "$(state)" = Running ]; then
  say "Tailscale already connected: $(on "$TS ip -4" | head -n 1)"
  exit 0
fi

NEED_TAILSCALE_KEY=1 with_secrets "$@"
read_password
host="$(on 'h="$(plutil -extract hostName raw /etc/headless/settings.json 2> /dev/null)"; [ -n "$h" ] || h="$(scutil --get LocalHostName)"; printf "%s" "$h"')"
copy_remote
server="${TAILSCALE_LOGIN_SERVER:--}"
if [ -n "$TAILSCALE_KEY_REF" ]; then
  KEY=""
  IFS= read -r KEY <&4 || true
  exec 4<&-
  [ -n "$KEY" ] || die "the store gave no Tailscale auth key for $TAILSCALE_KEY_REF"
  EXTRA_STDIN="$KEY" as_root "/bin/bash ~/.headless/remote/tailscale.sh key $host $server" || die "Tailscale did not join with the auth key"
  unset KEY PASSWORD
  [ "$(state)" = Running ] || die "Tailscale did not connect"
  say "Tailscale connected: $(on "$TS ip -4" | head -n 1)"
else
  as_root "/bin/bash ~/.headless/remote/tailscale.sh link $host $server" || die "Tailscale gave no sign-in link"
  unset PASSWORD
  say "open the link above and approve the Mac, then run: tailscale.sh $CONFIG --wait"
fi
