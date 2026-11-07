#!/bin/bash
# remote/tailscale.sh - start a Tailscale join on the Mac, run as root by
# tailscale.sh with sudo -S.
#
# usage: sudo -S bash tailscale.sh key HOST SERVER    auth key on standard input,
#                                                     after a --headless-stdin-- line
#        sudo -S bash tailscale.sh link HOST SERVER   print a sign-in link
# SERVER is - for Tailscale's own control server.
set -euo pipefail
die() { echo "headless: $*" >&2; exit 1; }
MODE="${1:?}" HOST="${2:?}" SERVER="${3:?}"
TS=/run/current-system/sw/bin/tailscale
[ "$(id -u)" -eq 0 ] || die "run tailscale.sh as root"
[[ "$HOST" =~ ^[A-Za-z0-9-]+$ ]] || die "HOST is not a plain name"
args=(up --hostname="$HOST")
if [ "$SERVER" != - ]; then
  [[ "$SERVER" =~ ^https?://[A-Za-z0-9.:/_-]+$ ]] || die "SERVER is not an http(s) address"
  args+=(--login-server="$SERVER")
fi
for _ in $(seq 30); do "$TS" status > /dev/null 2>&1 && break; "$TS" version > /dev/null 2>&1 && [ -S /var/run/tailscaled.socket ] && break; sleep 1; done

case "$MODE" in
  key)
    # Skip to the mark line (the line sudo read, if it needed one, comes first).
    KEY=""
    while IFS= read -r line && [ "$line" != --headless-stdin-- ]; do :; done
    IFS= read -r KEY || true
    exec < /dev/null
    [ -n "$KEY" ] || die "no auth key on standard input"
    file="$(mktemp /var/root/headless-ts-key.XXXXXX)"
    trap 'rm -f "$file"' EXIT
    chmod 0600 "$file"
    printf '%s\n' "$KEY" > "$file"
    unset KEY
    "$TS" "${args[@]}" --auth-key="file:$file" --timeout=120s
    ;;
  link)
    exec < /dev/null
    log=/var/root/headless-tailscale-up.log
    nohup "$TS" "${args[@]}" > "$log" 2>&1 &
    for _ in $(seq 60); do
      url="$("$TS" status --json 2> /dev/null | plutil -extract AuthURL raw - 2> /dev/null || true)"
      [ -n "$url" ] && { echo "Sign-in link: $url"; exit 0; }
      sleep 1
    done
    cat "$log" >&2
    die "no sign-in link appeared"
    ;;
  *) die "unknown mode $MODE" ;;
esac
