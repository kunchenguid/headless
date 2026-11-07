#!/bin/bash
# secret-run.sh - run a command with one secret on a file descriptor, read
# straight from the user's secret store. The secret never reaches a command
# line, an environment variable of this script, a file or this script's
# output; the agent only ever names the store entry.
#
# usage: secret-run.sh [--fd N] REF -- COMMAND [ARG...]
#
# COMMAND runs with the secret readable on descriptor N (default 3), then
# end of file. For two secrets, nest it:
#   secret-run.sh REF1 -- secret-run.sh --fd 4 REF2 -- COMMAND
#
# REF names where the secret lives:
#   av:NAME             Automic Vault (av inject --mode=fd); asks for approval
#   op:op://VAULT/ITEM/FIELD
#                       1Password CLI (op read), signed in
#   bw:ITEM             Bitwarden CLI (bw get password), unlocked
#   cmd:COMMAND         any command that prints the secret, run with sh -c
#   env:FILE:VAR        a KEY=value file only you may read (mode 600 or
#                       stricter, owned by you); last resort, see
#                       references/secrets.md
set -euo pipefail

die() { echo "secret-run: $*" >&2; exit 2; }

fd=3
if [ "${1-}" = --fd ]; then
  fd="${2-}"
  shift 2
fi
[[ "$fd" =~ ^[3-9]$ ]] || die "--fd takes a descriptor from 3 to 9"
ref="${1-}"
[ "${2-}" = -- ] || die "usage: secret-run.sh [--fd N] REF -- COMMAND [ARG...]"
shift 2
[ $# -gt 0 ] || die "no command to run"

case "$ref" in
  av:*)
    name="${ref#av:}"
    [[ "$name" =~ ^[A-Za-z_][A-Za-z0-9_.-]*$ ]] || die "av: needs a secret name"
    command -v av > /dev/null || die "the av command (Automic Vault) is not installed"
    exec av inject --mode=fd "+$name:$fd" -- "$@"
    ;;
  op:*)
    item="${ref#op:}"
    [[ "$item" == op://* ]] || die "op: needs an op://VAULT/ITEM/FIELD reference"
    command -v op > /dev/null || die "the op command (1Password CLI) is not installed"
    produce() { op read --no-newline "$item"; }
    ;;
  bw:*)
    item="${ref#bw:}"
    [ -n "$item" ] || die "bw: needs an item name or id"
    command -v bw > /dev/null || die "the bw command (Bitwarden CLI) is not installed"
    produce() { bw get password "$item"; }
    ;;
  cmd:*)
    producer="${ref#cmd:}"
    [ -n "$producer" ] || die "cmd: needs a command"
    produce() { /bin/sh -c "$producer"; }
    ;;
  env:*)
    rest="${ref#env:}"
    file="${rest%:*}"
    var="${rest##*:}"
    [ "$file" != "$rest" ] || die "env: needs FILE:VAR"
    [[ "$var" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || die "env: VAR is not a variable name"
    case "$file" in "~/"*) file="$HOME/${file#\~/}" ;; esac
    [ -f "$file" ] || die "env: $file does not exist"
    [ -O "$file" ] || die "env: $file is not yours"
    if [ -n "$(find "$file" -prune \( -perm -040 -o -perm -020 -o -perm -004 -o -perm -002 \))" ]; then
      die "env: $file can be read by others; run chmod 600 on it"
    fi
    grep -q "^$var=" "$file" || die "env: $file has no $var line"
    produce() {
      sed -n "s/^$var=//p" "$file" | head -n 1 \
        | sed -e "s/^\"\\(.*\\)\"\$/\\1/" -e "s/^'\\(.*\\)'\$/\\1/" | tr -d '\n'
    }
    ;;
  *) die "unknown store in '$ref'; use av:, op:, bw:, cmd: or env:" ;;
esac

# The secret goes through a pipe, never through this script's variables.
eval "exec $fd< <(produce)"
exec "$@"
