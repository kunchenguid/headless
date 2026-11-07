# shellcheck shell=bash disable=SC2034
# lib.sh - shared by the Mac step scripts beside it, and by the Linux ones
# (linux/lib.sh sources it); sourced, not run.
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

# Which account names LOGIN may be; Windows sets its own.
LOGIN_PATTERN='^[a-z_][a-z0-9_-]*$'
LOGIN_RULE="a plain account name"

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
  [[ "$LOGIN" =~ $LOGIN_PATTERN ]] || die "LOGIN in headless.env must be $LOGIN_RULE"
  [ -f "$SSH_KEY" ] && [ -f "$SSH_KEY.pub" ] || die "SSH_KEY $SSH_KEY or its .pub is missing"
  # Every step signs in without prompts, so a key with a passphrase must be
  # loaded in ssh-agent.
  if ! ssh-keygen -y -P '' -f "$SSH_KEY" > /dev/null 2>&1 \
    && ! ssh-add -L 2> /dev/null | grep -qF "$(cut -d' ' -f2 < "$SSH_KEY.pub")"; then
    die "$SSH_KEY has a passphrase and is not loaded in ssh-agent; run: ssh-add $SSH_KEY (on a Mac: ssh-add --apple-use-keychain $SSH_KEY)"
  fi
  [ -n "$PASSWORD_REF" ] || die "PASSWORD_REF in headless.env is empty"
  KNOWN_HOSTS="$CONFIG/known_hosts"
  SSH_OPTS=(-o "UserKnownHostsFile=\"$KNOWN_HOSTS\"" -o StrictHostKeyChecking=yes
    -o IdentitiesOnly=yes -i "$SSH_KEY" -o BatchMode=yes -o ConnectTimeout=15
    -o ServerAliveInterval=15 -o LogLevel=ERROR)
}

# on COMMAND: run COMMAND on the machine as LOGIN, by key.
on() { ssh "${SSH_OPTS[@]}" "$LOGIN@$ADDRESS" "$@"; }

# What first_sign_in and key_works run on the machine. A platform whose
# shell is not POSIX (Windows) sets its own before calling them.
# KEY_PROBE: a command that only succeeds. ADD_KEY_COMMAND: adds the public
# key line it reads on standard input to the account's keys; exit 3 means
# the account is not an administrator. HOST_KEY_FILE: where the machine
# keeps its ed25519 host key, for the user to compare.
KEY_PROBE=true
ADD_KEY_COMMAND='umask 077; mkdir -p ~/.ssh; touch ~/.ssh/authorized_keys; IFS= read -r k; grep -qxF "$k" ~/.ssh/authorized_keys || printf "%s\n" "$k" >> ~/.ssh/authorized_keys'
HOST_KEY_FILE=/etc/ssh/ssh_host_ed25519_key.pub

# key_works: true when key sign-in works. need_key: stop unless it does.
key_works() { [ -s "$KNOWN_HOSTS" ] && on "$KEY_PROBE" > /dev/null 2>&1; }
need_key() {
  key_works || die "key sign-in to $LOGIN@$ADDRESS does not work; run connect.sh first"
}

# first_sign_in HINT: pin the machine's ed25519 host key in the config
# folder on first use (and refuse a changed one), then, unless key sign-in
# already works, sign in once with the password from the store and add
# your public key. HINT says what to check when the machine gives no key.
# Run it before with_secrets: it wires the password itself when needed.
first_sign_in() {
  local scanned
  scanned="$(ssh-keyscan -T 10 -t ed25519 "$ADDRESS" 2> /dev/null | grep -v '^#' || true)"
  [ "$(printf '%s\n' "$scanned" | grep -c .)" -eq 1 ] || die "$ADDRESS gave no single ed25519 host key; $1"
  if [ -s "$KNOWN_HOSTS" ]; then
    [ "$(cut -d' ' -f2- < "$KNOWN_HOSTS")" = "$(printf '%s\n' "$scanned" | cut -d' ' -f2-)" ] \
      || die "$ADDRESS now shows a different host key than the one pinned in $KNOWN_HOSTS; stop and find out why"
  else
    printf '%s\n' "$scanned" > "$KNOWN_HOSTS"
    say "pinned host key $(ssh-keygen -lf "$KNOWN_HOSTS" | awk '{ print $2 }') (compare it at the machine with: ssh-keygen -lf $HOST_KEY_FILE)"
  fi

  if key_works; then
    say "key sign-in already works for $LOGIN@$ADDRESS"
    return 0
  fi
  with_secrets "${FIRST_SIGN_IN_ARGS[@]}"
  read_password
  # SSH asks this helper for the password; it prints it from its own
  # environment, never from a command line or a file.
  local tmp pub rc=0
  tmp="$(mktemp -d)"
  # shellcheck disable=SC2064 # tmp is fixed now
  trap "rm -rf '$tmp'" EXIT
  printf '#!/bin/sh\nprintf "%%s\\n" "$HEADLESS_ASKPASS_SECRET"\n' > "$tmp/askpass"
  chmod 0700 "$tmp/askpass"
  pub="$(head -n 1 "$SSH_KEY.pub")"
  printf '%s\n' "$pub" | HEADLESS_ASKPASS_SECRET="$PASSWORD" SSH_ASKPASS="$tmp/askpass" SSH_ASKPASS_REQUIRE=force \
    ssh -o "UserKnownHostsFile=\"$KNOWN_HOSTS\"" -o StrictHostKeyChecking=yes -o PubkeyAuthentication=no \
      -o PreferredAuthentications=password,keyboard-interactive -o NumberOfPasswordPrompts=1 \
      -o ConnectTimeout=15 -o LogLevel=ERROR "$LOGIN@$ADDRESS" "$ADD_KEY_COMMAND" \
    || rc=$?
  [ "$rc" != 3 ] || die "$LOGIN on $ADDRESS is not an administrator; the skill needs an administrator account"
  [ "$rc" != 127 ] || die "$ADDRESS signed $LOGIN in but could not run the command that adds your key; it does not run the system this part of the skill is for"
  [ "$rc" = 0 ] || die "password sign-in to $LOGIN@$ADDRESS failed; check the password in $PASSWORD_REF and that SSH allows $LOGIN to sign in with a password"
  unset PASSWORD
  key_works || die "your key was added but key sign-in still fails"
  say "added your key to $LOGIN@$ADDRESS; key sign-in works"
}

# tar_c ARGS...: tar to standard output, without the macOS extended
# attributes that GNU tar (or Windows' tar) on the machine would warn about.
tar_c() {
  if tar --version 2> /dev/null | grep -q bsdtar; then
    COPYFILE_DISABLE=1 tar --no-xattrs --no-mac-metadata -cf - "$@"
  else
    tar -cf - "$@"
  fi
}

# copy_remote: put the remote step scripts in ~/.headless/remote: the
# shared ones (scripts/remote) and this platform's.
copy_remote() {
  tar -cf - -C "$SCRIPTS/remote" . -C "$REMOTE_SRC" . | on 'rm -rf ~/.headless/remote && mkdir -p -m 0700 ~/.headless/remote && tar -xf - -C ~/.headless/remote'
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

# new_config DIR OPTION...: new-config.sh's work, for each platform's
# entry point. The caller sets EXTRAS (the platform's extras, all on unless
# named with --extra-off) and TEMPLATE (a folder whose flake.nix and
# machine.nix, or the files TEMPLATE_FILES names, a new config folder starts
# with, or empty).
new_config() {
  local DIR="${1:?usage: new-config.sh DIR --address ADDRESS --login LOGIN --password-ref REF [options]}"
  shift
  local ADDRESS="" LOGIN="" PASSWORD_REF="" SSH_KEY="~/.ssh/id_ed25519" HOST_NAME=""
  local AUTO_LOGIN=true KEY_ONLY=true TAILSCALE=false TAILSCALE_KEY_REF="" TAILSCALE_LOGIN_SERVER=""
  local OFF=" " key_path PUBKEY f e v host_json=null extras_json=""
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
  [[ "$LOGIN" =~ $LOGIN_PATTERN ]] || die "--login must be $LOGIN_RULE"
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

  if [ -n "$TEMPLATE" ]; then
    for f in ${TEMPLATE_FILES:-flake.nix machine.nix}; do
      [ -e "$DIR/$f" ] || cp "$TEMPLATE/$f" "$DIR/$f"
    done
  fi

  [ -z "$HOST_NAME" ] || host_json="\"$HOST_NAME\""
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
}

# tailscale_join "$@": tailscale.sh's work, for each platform's entry
# point, after load_config. The caller sets TS (the tailscale command on the
# machine) and defines ts_check (stop unless the machine's settings turn
# Tailscale on) and ts_host (print the name to join with).
tailscale_join() {
  need_key
  ts_check
  # shellcheck disable=SC2016 # runs on the machine
  ts_state() { on "$TS"' status --json 2> /dev/null | sed -n "s/^[[:space:]]*\"BackendState\":[[:space:]]*\"\([A-Za-z]*\)\".*/\1/p" | head -n 1' || true; }
  ts_ip4() { on "$TS ip -4" | head -n 1; }

  if [ "${2-}" = --wait ]; then
    local start=$SECONDS
    while [ $((SECONDS - start)) -lt 600 ]; do
      [ "$(ts_state)" = Running ] && { say "Tailscale connected: $(ts_ip4)"; exit 0; }
      sleep 5
    done
    die "Tailscale is not connected after 10 minutes; run tailscale.sh again for a fresh link"
  fi
  if [ "$(ts_state)" = Running ]; then
    say "Tailscale already connected: $(ts_ip4)"
    exit 0
  fi

  NEED_TAILSCALE_KEY=1 with_secrets "$@"
  read_password
  local host server KEY
  host="$(ts_host)"
  copy_remote
  server="${TAILSCALE_LOGIN_SERVER:--}"
  if [ -n "$TAILSCALE_KEY_REF" ]; then
    KEY=""
    IFS= read -r KEY <&4 || true
    exec 4<&-
    [ -n "$KEY" ] || die "the store gave no Tailscale auth key for $TAILSCALE_KEY_REF"
    EXTRA_STDIN="$KEY" as_root "/usr/bin/env bash ~/.headless/remote/tailscale.sh key $host $server" || die "Tailscale did not join with the auth key"
    unset KEY PASSWORD
    [ "$(ts_state)" = Running ] || die "Tailscale did not connect"
    say "Tailscale connected: $(ts_ip4)"
  else
    as_root "/usr/bin/env bash ~/.headless/remote/tailscale.sh link $host $server" || die "Tailscale gave no sign-in link"
    unset PASSWORD
    say "open the link above and approve the machine, then run: tailscale.sh $CONFIG --wait"
  fi
}
