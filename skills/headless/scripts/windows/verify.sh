#!/bin/bash
# verify.sh - read every headless setting back from the Windows machine and
# compare it with what it should be (the machine's record, written by
# apply.sh). Needs no password: it signs in by key and changes nothing.
#
# usage: verify.sh DIR
#
# Prints one line per setting, "ok", "FAIL" or "n/a", and exits 1 on any FAIL.
# shellcheck source=skills/headless/scripts/windows/lib.sh
. "$(dirname "$0")/lib.sh"
load_config "${1-}"
fails=0
check() { if [ "$1" = ok ]; then echo "ok    $2"; else echo "FAIL  $2"; fails=$((fails + 1)); fi; }

if key_works; then check ok "key sign-in as $LOGIN"; else check fail "key sign-in as $LOGIN"; echo "headless: cannot read anything more" >&2; exit 1; fi
copy_remote
if out="$(run_remote verify < /dev/null | tr -d '\r')" && [ -n "$out" ]; then
  printf '%s\n' "$out"
  fails=$((fails + $(printf '%s\n' "$out" | grep -c '^FAIL' || true)))
else
  [ -z "$out" ] || printf '%s\n' "$out"
  check fail "reading the settings on $ADDRESS"
fi

# Password sign-in must be refused when settings say key only.
if printf '%s\n' "$out" | grep -q 'sshd: password sign-in off\|sshd -T could not be read'; then
  methods="$(ssh -o "UserKnownHostsFile=\"$KNOWN_HOSTS\"" -o StrictHostKeyChecking=yes -o PubkeyAuthentication=no \
    -o PreferredAuthentications=password,keyboard-interactive -o BatchMode=yes -o ConnectTimeout=15 \
    "$LOGIN@$ADDRESS" exit 2>&1 || true)"
  # The server lists the ways it still accepts; neither password way may be
  # among them.
  offered="$(printf '%s\n' "$methods" | sed -n 's/.*Permission denied (\([^)]*\)).*/\1/p' | head -n 1)"
  if [ -n "$offered" ] && ! printf '%s' "$offered" | grep -qE 'password|keyboard-interactive'; then
    check ok "password sign-in refused (key only)"
  else
    check fail "password sign-in refused (key only): $methods"
  fi
fi
[ "$fails" -eq 0 ] || { echo "headless: $fails setting(s) do not match" >&2; exit 1; }
echo "headless: every setting matches"
