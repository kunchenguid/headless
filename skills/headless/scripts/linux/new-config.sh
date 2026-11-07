#!/bin/bash
# new-config.sh - make a Linux machine's config folder on this computer, or
# update the settings of one.
#
# usage: new-config.sh DIR --address ADDRESS --login LOGIN --password-ref REF
#          [--ssh-key PATH] [--host-name NAME] [--no-auto-login]
#          [--tailscale] [--tailscale-key-ref REF] [--tailscale-login-server URL]
#          [--extra-off NAME]... [--keep-password-ssh]
#
# DIR becomes a git folder holding settings.json (the headless settings,
# the same for NixOS and for the distro-neutral script) and headless.env
# (how to reach the machine and where the password lives; no secret). The
# NixOS files (flake.nix, machine.nix, system.nix) arrive later, from
# apply.sh on a NixOS machine or install-nixos.sh; an existing DIR keeps
# them. settings.json and headless.env are written again from the options
# given.
#
# Extras, both on unless named with --extra-off: neverSleep, autoUpdates.
set -euo pipefail
die() { echo "headless: $*" >&2; exit 1; }

DIR="${1:?usage: new-config.sh DIR --address ADDRESS --login LOGIN --password-ref REF [options]}"
shift
ADDRESS="" LOGIN="" PASSWORD_REF="" SSH_KEY="~/.ssh/id_ed25519" HOST_NAME=""
AUTO_LOGIN=true KEY_ONLY=true TAILSCALE=false TAILSCALE_KEY_REF="" TAILSCALE_LOGIN_SERVER=""
EXTRAS=(neverSleep autoUpdates)
OFF=" "
while [ $# -gt 0 ]; do
  case "$1" in
    --address) ADDRESS="${2-}"; shift 2 ;;
    --login) LOGIN="${2-}"; shift 2 ;;
    --password-ref) PASSWORD_REF="${2-}"; shift 2 ;;
    --ssh-key) SSH_KEY="${2-}"; shift 2 ;;
    --host-name) HOST_NAME="${2-}"; shift 2 ;;
    --no-auto-login) AUTO_LOGIN=false; shift ;;
    --keep-password-ssh) KEY_ONLY=false; shift ;;
    --tailscale) TAILSCALE=true; shift ;;
    --tailscale-key-ref) TAILSCALE_KEY_REF="${2-}"; shift 2 ;;
    --tailscale-login-server) TAILSCALE_LOGIN_SERVER="${2-}"; shift 2 ;;
    --extra-off)
      [[ " ${EXTRAS[*]} " == *" ${2-} "* ]] || die "unknown extra '${2-}'; extras are ${EXTRAS[*]}"
      OFF="$OFF${2} "; shift 2 ;;
    *) die "unknown option $1" ;;
  esac
done

[[ "$ADDRESS" =~ ^[A-Za-z0-9.:_-]+$ ]] || die "--address must be a plain address or name"
[[ "$LOGIN" =~ ^[a-z_][a-z0-9_-]*$ ]] || die "--login must be a plain account name"
[ "$LOGIN" != root ] || die "--login must be an admin account other than root"
[ -n "$PASSWORD_REF" ] || die "--password-ref names the store entry holding the password"
[ -z "$HOST_NAME" ] || [[ "$HOST_NAME" =~ ^[A-Za-z0-9][A-Za-z0-9-]{0,62}$ ]] || die "--host-name must be letters, digits and dashes"
[ -z "$TAILSCALE_LOGIN_SERVER" ] || [[ "$TAILSCALE_LOGIN_SERVER" =~ ^https?://[A-Za-z0-9.:/_-]+$ ]] || die "--tailscale-login-server must be an http(s) address"
key_path="$SSH_KEY"
case "$key_path" in "~/"*) key_path="$HOME/${key_path#\~/}" ;; esac
[ -f "$key_path.pub" ] || die "$key_path.pub does not exist; make a key with ssh-keygen -t ed25519 first"
PUBKEY="$(cut -d' ' -f1-3 < "$key_path.pub" | head -n 1)"
[[ "$PUBKEY" =~ ^[a-z0-9@.-]+\ [A-Za-z0-9+/=]+(\ [^\"\\]*)?$ ]] || die "$key_path.pub is not a plain public key line"

mkdir -p "$DIR"
DIR="$(cd "$DIR" && pwd)"
case "$PASSWORD_REF" in
  env:*)
    f="${PASSWORD_REF#env:}"; f="${f%:*}"
    case "$f" in "~/"*) f="$HOME/${f#\~/}" ;; esac
    case "$(cd "$(dirname "$f")" 2> /dev/null && pwd)/" in
      "$DIR"/*) die "keep the env file outside the config folder, so it is never copied or committed" ;;
    esac ;;
esac

host_json=null
[ -z "$HOST_NAME" ] || host_json="\"$HOST_NAME\""
extras_json=""
for e in "${EXTRAS[@]}"; do
  v=true
  [[ "$OFF" != *" $e "* ]] || v=false
  extras_json="$extras_json${extras_json:+,}
    \"$e\": $v"
done
cat > "$DIR/settings.json" <<JSON
{
  "user": "$LOGIN",
  "hostName": $host_json,
  "sshKeys": [
    "$PUBKEY"
  ],
  "keyOnlySsh": $KEY_ONLY,
  "autoLogin": $AUTO_LOGIN,
  "tailscale": { "enable": $TAILSCALE },
  "extras": {$extras_json
  }
}
JSON

cat > "$DIR/headless.env" <<ENV
# How the headless skill reaches this machine. No secret belongs here:
# PASSWORD_REF only names the store entry that holds the password.
ADDRESS=$ADDRESS
LOGIN=$LOGIN
SSH_KEY=$SSH_KEY
PASSWORD_REF=$PASSWORD_REF
TAILSCALE_KEY_REF=$TAILSCALE_KEY_REF
TAILSCALE_LOGIN_SERVER=$TAILSCALE_LOGIN_SERVER
ENV

if command -v git > /dev/null && git --version > /dev/null 2>&1; then
  [ -d "$DIR/.git" ] || git -C "$DIR" init -q
  git -C "$DIR" add -A
fi
echo "headless: config folder ready at $DIR"
