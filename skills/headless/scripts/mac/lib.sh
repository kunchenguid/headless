# shellcheck shell=bash disable=SC2034
# lib.sh - shared by the Mac step scripts beside it; sourced, not run.
#
# Every step takes the machine's config folder (made by new-config.sh). Its
# headless.env names how to reach the machine and where the password lives;
# it holds no secret:
#   ADDRESS=192.168.1.20     the machine's address or name
#   LOGIN=admin              the admin account
#   SSH_KEY=~/.ssh/id_ed25519
#                            your private key; its .pub goes on the machine
#   PASSWORD_REF=av:NAME     the store entry with the admin password
#   TAILSCALE_KEY_REF=...    optional: the store entry with a Tailscale auth key
#   TAILSCALE_LOGIN_SERVER=  optional: a control server other than Tailscale's
set -euo pipefail
# shellcheck disable=SC2034 # the step scripts use these

SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REMOTE_SRC="$SCRIPTS/mac/remote"
NIX=/nix/var/nix/profiles/default/bin/nix

die() { echo "headless: $*" >&2; exit 1; }
say() { echo "headless: $*"; }

# load_config DIR: read DIR/headless.env into ADDRESS, LOGIN, SSH_KEY,
# PASSWORD_REF, TAILSCALE_KEY_REF and TAILSCALE_LOGIN_SERVER, and set the
# SSH options every step uses.
load_config() {
  CONFIG="$(cd "${1:?give the config folder of the machine}" && pwd)"
  local env="$CONFIG/headless.env"
  [ -f "$env" ] || die "$CONFIG has no headless.env; run new-config.sh first"
  conf() { sed -n "s/^$1=//p" "$env" | tail -n 1; }
  ADDRESS="$(conf ADDRESS)"
  LOGIN="$(conf LOGIN)"
  SSH_KEY="$(conf SSH_KEY)"
  PASSWORD_REF="$(conf PASSWORD_REF)"
  TAILSCALE_KEY_REF="$(conf TAILSCALE_KEY_REF)"
  TAILSCALE_LOGIN_SERVER="$(conf TAILSCALE_LOGIN_SERVER)"
  case "$SSH_KEY" in "~/"*) SSH_KEY="$HOME/${SSH_KEY#\~/}" ;; esac
  [[ "$ADDRESS" =~ ^[A-Za-z0-9.:_-]+$ ]] || die "ADDRESS in headless.env is not a plain address"
  [[ "$LOGIN" =~ ^[a-z_][a-z0-9_-]*$ ]] || die "LOGIN in headless.env is not a plain account name"
  [ -f "$SSH_KEY" ] && [ -f "$SSH_KEY.pub" ] || die "SSH_KEY $SSH_KEY or its .pub is missing"
  [ -n "$PASSWORD_REF" ] || die "PASSWORD_REF in headless.env is empty"
  KNOWN_HOSTS="$CONFIG/known_hosts"
  SSH_OPTS=(-o "UserKnownHostsFile=\"$KNOWN_HOSTS\"" -o StrictHostKeyChecking=yes
    -o IdentitiesOnly=yes -i "$SSH_KEY" -o BatchMode=yes -o ConnectTimeout=15
    -o ServerAliveInterval=15 -o LogLevel=ERROR)
}

# on COMMAND: run COMMAND on the machine as LOGIN, by key.
on() { ssh "${SSH_OPTS[@]}" "$LOGIN@$ADDRESS" "$@"; }

# key_works: true when key sign-in works. need_key: stop unless it does.
# Key sign-in runs without prompts, so a key with a passphrase must be
# loaded in ssh-agent first.
key_works() { [ -s "$KNOWN_HOSTS" ] && on true > /dev/null 2>&1; }
need_key() {
  key_works || die "key sign-in to $LOGIN@$ADDRESS does not work. Run connect.sh first; if your key has a passphrase, load it with: ssh-add $SSH_KEY"
}

# copy_remote: put the remote step scripts in ~/.headless/remote.
copy_remote() {
  tar -C "$REMOTE_SRC" -cf - . | on 'rm -rf ~/.headless/remote && mkdir -p -m 0700 ~/.headless/remote && tar -xf - -C ~/.headless/remote'
}

# with_secrets "$@": run this script again with the admin password on
# descriptor 3 (and, when NEED_TAILSCALE_KEY=1 and a key entry is set, the
# Tailscale auth key on descriptor 4), unless that already happened.
with_secrets() {
  [ "${HEADLESS_SECRETS_WIRED-}" = 1 ] && return 0
  export HEADLESS_SECRETS_WIRED=1
  if [ "${NEED_TAILSCALE_KEY-}" = 1 ] && [ -n "$TAILSCALE_KEY_REF" ]; then
    exec "$SCRIPTS/secret-run.sh" "$PASSWORD_REF" -- \
      "$SCRIPTS/secret-run.sh" --fd 4 "$TAILSCALE_KEY_REF" -- "$0" "$@"
  fi
  exec "$SCRIPTS/secret-run.sh" "$PASSWORD_REF" -- "$0" "$@"
}

# read_password: the password from descriptor 3 into PASSWORD (this shell
# only; never exported, never printed).
read_password() {
  PASSWORD=""
  IFS= read -r PASSWORD <&3 || true
  exec 3<&-
  [ -n "$PASSWORD" ] || die "the store gave no password for $PASSWORD_REF"
}

# as_root COMMAND: run COMMAND on the machine as root, the password piped
# to sudo -S. Lines given in EXTRA_STDIN follow a STDIN_MARK line: sudo
# reads no password when it needs none, so COMMAND skips to that line
# before reading its own input (remote/*.sh do).
STDIN_MARK=--headless-stdin--
as_root() {
  { printf '%s\n' "$PASSWORD"; [ -z "${EXTRA_STDIN-}" ] || printf '%s\n%s\n' "$STDIN_MARK" "$EXTRA_STDIN"; } \
    | on "sudo -S -p '' $1"
}
