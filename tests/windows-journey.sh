#!/bin/bash
# tests/windows-journey.sh - the skill's Windows journey end to end against
# one Windows machine, as an agent following SKILL.md runs it: new config,
# first sign-in (twice: the second needs no password), apply, verify, a
# second apply that changes nothing, and optionally restart and verify
# again. Then it checks the transcript never holds the password.
# Intent: the Windows journey runs in CI and on VMs, a second apply changes
# nothing (the plan's "running it a second time changes nothing"), and a
# grep of the whole log for the password finds nothing; with --restart it
# also proves the machine comes back signed in by itself.
#
# usage: tests/windows-journey.sh ADDRESS LOGIN ENV_FILE CONFIG_DIR
#          [--restart] [-- NEW_CONFIG_OPTION...]
#
# ENV_FILE holds HEADLESS_PASSWORD=... (mode 600).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WIN="$ROOT/skills/headless/scripts/windows"
ADDRESS="${1:?}" LOGIN="${2:?}" ENV_FILE="${3:?}" DIR="${4:?}"
shift 4
RESTART=0
while [ $# -gt 0 ]; do
  case "$1" in
    --restart) RESTART=1; shift ;;
    --) shift; break ;;
    *) echo "unknown option $1" >&2; exit 2 ;;
  esac
done
mkdir -p "$(dirname "$DIR")"
log="$DIR.journey.log"
: > "$log"
step() { echo "== $*" | tee -a "$log"; "$@" 2>&1 | tee -a "$log"; return "${PIPESTATUS[0]}"; }
# last_step: the last step's output, everything after the last "== " line.
last_step() { awk '/^== /{buf=""} {buf=buf $0 "\n"} END{printf "%s", buf}' "$log"; }

step "$WIN/new-config.sh" "$DIR" --address "$ADDRESS" --login "$LOGIN" \
  --password-ref "env:$ENV_FILE:HEADLESS_PASSWORD" --ssh-key "${SSH_KEY:-$HOME/.ssh/id_ed25519}" "$@"
step "$WIN/connect.sh" "$DIR"
step "$WIN/connect.sh" "$DIR"
last_step | grep -q 'key sign-in already works' || { echo "FAIL  the second connect.sh did not find the key working" | tee -a "$log"; exit 1; }
step "$WIN/apply.sh" "$DIR"
step "$WIN/verify.sh" "$DIR"
step "$WIN/apply.sh" "$DIR"
if last_step | grep -q 'headless: changed:'; then echo "FAIL  the second apply changed something" | tee -a "$log"; exit 1; fi
echo "ok    the second apply changed nothing" | tee -a "$log"
if [ "$RESTART" = 1 ]; then
  step "$WIN/restart.sh" "$DIR"
  step "$WIN/verify.sh" "$DIR"
fi

# The password must appear nowhere in what the journey printed.
pw="$(sed -n 's/^HEADLESS_PASSWORD=//p' "$ENV_FILE")"
if grep -qF -- "$pw" "$log"; then echo "FAIL  the journey's output holds the password"; exit 1; fi
echo "ok    the journey's output never holds the password ($(wc -l < "$log" | tr -d ' ') lines checked)"
