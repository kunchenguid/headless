#!/bin/bash
# admin.sh - the admin session: installs Determinate Nix and, when
# settings.json turns automatic sign-in on, stores the sign-in password
# macOS uses at start-up. The password goes from the store to sudo -S on
# the machine; it never reaches a command line, a log or this output.
#
# usage: admin.sh DIR
#
# Run connect.sh first. It is safe to run again.
# shellcheck source=skills/headless/scripts/mac/lib.sh
. "$(dirname "$0")/lib.sh"
load_config "${1-}"
key_works || die "key sign-in to $LOGIN@$ADDRESS does not work yet; run connect.sh first"
with_secrets "$@"
read_password

copy_remote
on 'cat > ~/.headless/remote/settings.json' < "$CONFIG/settings.json"
# The password twice: once for sudo, once for the automatic sign-in it
# stores (the same account's password).
EXTRA_STDIN="$PASSWORD" as_root "/bin/bash ~/.headless/remote/admin.sh $LOGIN" \
  || die "the admin session failed; its output above says where"
unset PASSWORD
say "admin session done"
