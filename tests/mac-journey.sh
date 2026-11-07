#!/bin/bash
# tests/mac-journey.sh - the skill's Mac journey end to end against one Mac,
# as an agent following SKILL.md runs it: new config, first sign-in, admin
# session, apply, verify, and optionally restart and verify again. Then it
# checks the transcript never holds the password.
# Intent: the Mac journey runs in CI over SSH and a grep of its whole log for
# the password finds nothing; with --restart it also proves the live restart.
#
# usage: tests/mac-journey.sh ADDRESS LOGIN ENV_FILE CONFIG_DIR [--restart] [-- NEW_CONFIG_OPTION...]
#
# ENV_FILE holds HEADLESS_PASSWORD=... (mode 600). The journey builds the
# module from this checkout (apply.sh --headless-source).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MAC="$ROOT/skills/headless/scripts/mac"
ADDRESS="${1:?}" LOGIN="${2:?}" ENV_FILE="${3:?}" DIR="${4:?}"
shift 4
RESTART=0
[ "${1-}" != --restart ] || { RESTART=1; shift; }
[ "${1-}" != -- ] || shift
mkdir -p "$(dirname "$DIR")"
log="$DIR.journey.log"
: > "$log"
step() { echo "== $*" | tee -a "$log"; "$@" 2>&1 | tee -a "$log"; return "${PIPESTATUS[0]}"; }

step "$MAC/new-config.sh" "$DIR" --address "$ADDRESS" --login "$LOGIN" \
  --password-ref "env:$ENV_FILE:HEADLESS_PASSWORD" --ssh-key "${SSH_KEY:-$HOME/.ssh/id_ed25519}" "$@"
step "$MAC/connect.sh" "$DIR"
step "$MAC/admin.sh" "$DIR"
step "$MAC/apply.sh" "$DIR" --headless-source "$ROOT"
step "$MAC/verify.sh" "$DIR"
if [ "$RESTART" = 1 ]; then
  step "$MAC/restart.sh" "$DIR"
  step "$MAC/verify.sh" "$DIR"
fi

# The password must appear nowhere in what the journey printed.
pw="$(sed -n 's/^HEADLESS_PASSWORD=//p' "$ENV_FILE")"
if grep -qF -- "$pw" "$log"; then echo "FAIL  the journey's output holds the password"; exit 1; fi
echo "ok    the journey's output never holds the password ($(wc -l < "$log" | tr -d ' ') lines checked)"
