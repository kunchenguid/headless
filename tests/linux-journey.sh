#!/bin/bash
# tests/linux-journey.sh - the skill's Linux journey end to end against one
# Linux machine, as an agent following SKILL.md runs it: new config, first
# sign-in, then either apply (NixOS, or the distro-neutral script) or
# install NixOS with nixos-anywhere and apply again, then verify, and
# optionally restart and verify again. Then it checks the transcript never
# holds the password.
# Intent: the Linux journeys (NixOS module, nixos-anywhere install,
# distro-neutral script) run in CI and on VMs, and a grep of each whole log
# for the password finds nothing; with --restart it also proves the
# machine comes back with the user's session started by itself.
#
# usage: tests/linux-journey.sh ADDRESS LOGIN ENV_FILE CONFIG_DIR
#          [--install DISK] [--restart] [-- NEW_CONFIG_OPTION...]
#
# ENV_FILE holds HEADLESS_PASSWORD=... (mode 600). NixOS builds use the
# module from this checkout (--headless-source).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LINUX="$ROOT/skills/headless/scripts/linux"
ADDRESS="${1:?}" LOGIN="${2:?}" ENV_FILE="${3:?}" DIR="${4:?}"
shift 4
RESTART=0 DISK=""
while [ $# -gt 0 ]; do
  case "$1" in
    --restart) RESTART=1; shift ;;
    --install) DISK="${2:?--install needs a disk}"; shift 2 ;;
    --) shift; break ;;
    *) echo "unknown option $1" >&2; exit 2 ;;
  esac
done
mkdir -p "$(dirname "$DIR")"
log="$DIR.journey.log"
: > "$log"
step() { echo "== $*" | tee -a "$log"; "$@" 2>&1 | tee -a "$log"; return "${PIPESTATUS[0]}"; }

step "$LINUX/new-config.sh" "$DIR" --address "$ADDRESS" --login "$LOGIN" \
  --password-ref "env:$ENV_FILE:HEADLESS_PASSWORD" --ssh-key "${SSH_KEY:-$HOME/.ssh/id_ed25519}" "$@"
step "$LINUX/connect.sh" "$DIR"
if [ -n "$DISK" ]; then
  step "$LINUX/install-nixos.sh" "$DIR" --list-disks
  step "$LINUX/install-nixos.sh" "$DIR" --disk "$DISK" --yes-wipe --headless-source "$ROOT"
  step "$LINUX/verify.sh" "$DIR"
fi
# Apply a NixOS machine against this checkout; the script path takes no source.
# connect.sh said which system the machine runs (a new sign-in right after
# it may be held back by the server's own penalty for the first key try).
src=()
if [ -n "$DISK" ] || grep -q '^headless: .* runs NixOS ' "$log"; then
  src=(--headless-source "$ROOT")
fi
step "$LINUX/apply.sh" "$DIR" ${src[@]+"${src[@]}"}
step "$LINUX/verify.sh" "$DIR"
# A second apply changes nothing on the script path.
if [ ${#src[@]} -eq 0 ]; then
  step "$LINUX/apply.sh" "$DIR"
  # The last step's output: everything after the last "== " line.
  last="$(awk '/^== /{buf=""} {buf=buf $0 "\n"} END{printf "%s", buf}' "$log")"
  if printf '%s' "$last" | grep -q 'headless: changed:'; then echo "FAIL  the second apply changed something" | tee -a "$log"; exit 1; fi
  echo "ok    the second apply changed nothing" | tee -a "$log"
fi
if [ "$RESTART" = 1 ]; then
  step "$LINUX/restart.sh" "$DIR"
  step "$LINUX/verify.sh" "$DIR"
fi

# The password must appear nowhere in what the journey printed.
pw="$(sed -n 's/^HEADLESS_PASSWORD=//p' "$ENV_FILE")"
if grep -qF -- "$pw" "$log"; then echo "FAIL  the journey's output holds the password"; exit 1; fi
echo "ok    the journey's output never holds the password ($(wc -l < "$log" | tr -d ' ') lines checked)"
