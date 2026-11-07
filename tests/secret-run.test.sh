#!/bin/bash
# tests/secret-run.test.sh - the secret helper hands the password to the
# command on a descriptor, never prints it, and refuses an env file others
# can read. Intent: the password sits in a secret store the agent never
# reads directly (the skill's password handling, references/secrets.md).
#
# usage: tests/secret-run.test.sh
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
RUN="$HERE/../skills/headless/scripts/secret-run.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
fails=0
pass() { echo "ok    $1"; }
fail() { echo "FAIL  $1"; fails=$((fails + 1)); }

# A password with the characters that break naive quoting.
pw="c0rrect horse \$HOME 'q' \"d\" \\ ;|&"
printf 'OTHER=x\nHEADLESS_PASSWORD=%s\n' "$pw" > "$tmp/secrets.env"
chmod 600 "$tmp/secrets.env"
reader="$tmp/reader.sh"
printf '#!/bin/bash\nIFS= read -r got <&3 || true\n[ "$got" = "$1" ] && echo match || echo mismatch\n' > "$reader"
chmod +x "$reader"

out="$("$RUN" "env:$tmp/secrets.env:HEADLESS_PASSWORD" -- "$reader" "$pw" 2>&1)"
[ "$out" = match ] && pass "env store delivers the exact password on descriptor 3" || fail "env store: $out"

printf 'HEADLESS_PASSWORD="%s"\n' "$pw" > "$tmp/quoted.env"; chmod 600 "$tmp/quoted.env"
out="$("$RUN" "env:$tmp/quoted.env:HEADLESS_PASSWORD" -- "$reader" "$pw" 2>&1)"
[ "$out" = match ] && pass "env store strips surrounding quotes" || fail "env store quotes: $out"

chmod 644 "$tmp/secrets.env"
if out="$("$RUN" "env:$tmp/secrets.env:HEADLESS_PASSWORD" -- "$reader" "$pw" 2>&1)"; then
  fail "env store accepted a file others can read"
else
  printf '%s' "$out" | grep -q 'can be read by others' && pass "env store refuses a file others can read" || fail "refusal message: $out"
fi
chmod 600 "$tmp/secrets.env"

out="$("$RUN" "cmd:sed -n 's/^HEADLESS_PASSWORD=//p' '$tmp/secrets.env'" -- "$reader" "$pw" 2>&1)"
[ "$out" = match ] && pass "command store delivers the password" || fail "command store: $out"

out="$("$RUN" "env:$tmp/secrets.env:HEADLESS_PASSWORD" -- "$RUN" --fd 4 "cmd:printf tskey-test" -- \
  /bin/bash -c 'IFS= read -r a <&3; IFS= read -r b <&4; [ "$b" = tskey-test ] && [ -n "$a" ] && echo both' 2>&1)"
[ "$out" = both ] && pass "two secrets on descriptors 3 and 4" || fail "two secrets: $out"

# Nothing the helper itself prints may hold the password.
all="$("$RUN" "env:$tmp/secrets.env:HEADLESS_PASSWORD" -- /usr/bin/true 2>&1; "$RUN" "env:$tmp/secrets.env:NOPE" -- /usr/bin/true 2>&1 || true)"
printf '%s' "$all" | grep -qF "$pw" && fail "helper output holds the password" || pass "helper output never holds the password"

[ "$fails" -eq 0 ] || exit 1
