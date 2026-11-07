#!/bin/bash
# verify.sh - read every headless setting back from the Mac and compare it
# with what its system declares (/etc/headless/settings.json). Needs no
# password: it signs in by key and runs nothing as root.
#
# usage: verify.sh DIR
#
# Prints one line per setting, "ok" or "FAIL", and exits 1 on any FAIL.
# shellcheck source=skills/headless/scripts/mac/lib.sh
. "$(dirname "$0")/lib.sh"
load_config "${1-}"
fails=0
check() { if [ "$1" = ok ]; then echo "ok    $2"; else echo "FAIL  $2"; fails=$((fails + 1)); fi; }

if key_works; then check ok "key sign-in as $LOGIN"; else check fail "key sign-in as $LOGIN"; echo "headless: cannot read anything more" >&2; exit 1; fi
copy_remote
out="$(on '/bin/bash ~/.headless/remote/verify.sh')" || true
printf '%s\n' "$out"
fails=$((fails + $(printf '%s\n' "$out" | grep -c '^FAIL' || true)))

# Password sign-in must be refused when settings say key only.
if on 'plutil -extract keyOnlySsh raw /etc/headless/settings.json' 2> /dev/null | grep -qx true; then
  methods="$(ssh -o "UserKnownHostsFile=\"$KNOWN_HOSTS\"" -o StrictHostKeyChecking=yes -o PubkeyAuthentication=no \
    -o PreferredAuthentications=password,keyboard-interactive -o BatchMode=yes -o ConnectTimeout=15 \
    "$LOGIN@$ADDRESS" true 2>&1 || true)"
  if printf '%s' "$methods" | grep -q 'Permission denied (publickey)'; then
    check ok "password sign-in refused (key only)"
  else
    check fail "password sign-in refused (key only): $methods"
  fi
fi
[ "$fails" -eq 0 ] || { echo "headless: $fails setting(s) do not match" >&2; exit 1; }
echo "headless: every setting matches"
