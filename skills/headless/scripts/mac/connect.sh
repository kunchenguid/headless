#!/bin/bash
# connect.sh - the first sign-in: pin the Mac's host key in the config
# folder, sign in once with the password from the store, add your public key
# to the admin account, and check that key sign-in works.
#
# usage: connect.sh DIR
#
# It is safe to run again: a pinned host key must still match, and a key
# that already works needs no password at all.
# shellcheck source=skills/headless/scripts/mac/lib.sh
. "$(dirname "$0")/lib.sh"
load_config "${1-}"

# Pin the host key on first use, and refuse a changed one.
scanned="$(ssh-keyscan -T 10 -t ed25519 "$ADDRESS" 2> /dev/null | grep -v '^#' || true)"
[ "$(printf '%s\n' "$scanned" | grep -c .)" -eq 1 ] || die "$ADDRESS gave no single ed25519 host key; is Remote Login on?"
if [ -s "$KNOWN_HOSTS" ]; then
  [ "$(cut -d' ' -f2- < "$KNOWN_HOSTS")" = "$(printf '%s\n' "$scanned" | cut -d' ' -f2-)" ] \
    || die "$ADDRESS now shows a different host key than the one pinned in $KNOWN_HOSTS; stop and find out why"
else
  printf '%s\n' "$scanned" > "$KNOWN_HOSTS"
  say "pinned host key $(ssh-keygen -lf "$KNOWN_HOSTS" | awk '{ print $2 }') (compare it at the Mac with: ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub)"
fi

if key_works; then
  say "key sign-in already works for $LOGIN@$ADDRESS"
else
  with_secrets "$@"
  read_password
  # SSH asks this helper for the password; it prints it from its own
  # environment, never from a command line or a file.
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  printf '#!/bin/sh\nprintf "%%s\\n" "$HEADLESS_ASKPASS_SECRET"\n' > "$tmp/askpass"
  chmod 0700 "$tmp/askpass"
  pub="$(head -n 1 "$SSH_KEY.pub")"
  printf '%s\n' "$pub" | HEADLESS_ASKPASS_SECRET="$PASSWORD" SSH_ASKPASS="$tmp/askpass" SSH_ASKPASS_REQUIRE=force \
    ssh -o "UserKnownHostsFile=\"$KNOWN_HOSTS\"" -o StrictHostKeyChecking=yes -o PubkeyAuthentication=no \
      -o PreferredAuthentications=password,keyboard-interactive -o NumberOfPasswordPrompts=1 \
      -o ConnectTimeout=15 -o LogLevel=ERROR "$LOGIN@$ADDRESS" \
      'umask 077; mkdir -p ~/.ssh; touch ~/.ssh/authorized_keys; IFS= read -r k; grep -qxF "$k" ~/.ssh/authorized_keys || printf "%s\n" "$k" >> ~/.ssh/authorized_keys' \
    || die "password sign-in to $LOGIN@$ADDRESS failed; check the password in $PASSWORD_REF and that Remote Login allows $LOGIN"
  unset PASSWORD
  key_works || die "your key was added but key sign-in still fails; if your key has a passphrase, load it with: ssh-add $SSH_KEY, then run connect.sh again"
  say "added your key to $LOGIN@$ADDRESS; key sign-in works"
fi

facts="$(on 'printf "%s %s %s\n" "$(uname -s)" "$(uname -m)" "$(sw_vers -productVersion)"; id -Gn')"
read -r os arch version <<< "$(printf '%s\n' "$facts" | head -n 1)"
[ "$os" = Darwin ] || die "$ADDRESS is not a Mac ($os); this part of the skill is for macOS"
[ "$arch" = arm64 ] || die "$ADDRESS is an $arch Mac; the skill supports Apple silicon only"
printf '%s\n' "$facts" | tail -n 1 | tr ' ' '\n' | grep -qx admin || die "$LOGIN is not an administrator on $ADDRESS"
say "$ADDRESS is macOS $version on Apple silicon and $LOGIN is an administrator"
