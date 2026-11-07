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
TS=tailscale
ts_check() {
  on 'grep -qx TAILSCALE=true /etc/headless/settings.env' 2> /dev/null \
    || die "Tailscale is off on $ADDRESS; set \"tailscale\": { \"enable\": true } in settings.json and run apply.sh"
}
ts_host() { on 'h="$(sed -n "s/^HOST_NAME=//p" /etc/headless/settings.env)"; [ -n "$h" ] || h="$(hostname)"; printf "%s" "$h"'; }
tailscale_join "$@"
