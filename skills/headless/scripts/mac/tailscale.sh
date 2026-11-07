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
ts_check() {
  on 'test ! -d /Applications/Tailscale.app' || die "the Tailscale app is already on $ADDRESS; leave it as it is and keep \"tailscale\" off in settings.json"
  on 'plutil -extract tailscale raw /etc/headless/settings.json' 2> /dev/null | grep -qx true \
    || die "Tailscale is off in the Mac's system; set \"tailscale\": { \"enable\": true } in settings.json and run apply.sh"
}
ts_host() { on 'h="$(plutil -extract hostName raw /etc/headless/settings.json 2> /dev/null)"; [ -n "$h" ] || h="$(scutil --get LocalHostName)"; printf "%s" "$h"'; }
tailscale_join "$@"
