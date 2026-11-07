#!/bin/bash
# apply.sh - copy the config folder to the Mac, build its system there and
# switch to it. The password comes from the store each time, for sudo -S on
# the Mac; the Mac keeps no passwordless admin rule.
#
# usage: apply.sh DIR [--headless-source PATH]
#
#   --headless-source PATH  build against this checkout of the headless
#                           flake instead of the one flake.lock pins (for
#                           trying changes to the module itself)
#
# The first run writes flake.lock on the Mac and copies it back into DIR;
# commit it there. Run admin.sh first.
# shellcheck source=skills/headless/scripts/mac/lib.sh
. "$(dirname "$0")/lib.sh"
load_config "${1-}"
shift
SOURCE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --headless-source) SOURCE="$(cd "${2:?--headless-source needs a path}" && pwd)"; shift 2 ;;
    *) die "unknown option $1" ;;
  esac
done
need_key
on "test -x $NIX" || die "Nix is not on $ADDRESS yet; run admin.sh first"
# The module's Tailscale daemon must not run beside the Tailscale app.
if on 'plutil -extract tailscale.enable raw -' < "$CONFIG/settings.json" 2> /dev/null | grep -qx true \
  && on 'test -d /Applications/Tailscale.app'; then
  die "the Tailscale app is on $ADDRESS; leave it as it is and set \"tailscale\": { \"enable\": false } in settings.json"
fi
set -- "$CONFIG" ${SOURCE:+--headless-source "$SOURCE"}
with_secrets "$@"
read_password

say "copying $CONFIG to $ADDRESS"
copy_remote
tar -C "$CONFIG" --exclude .git --exclude known_hosts -cf - . \
  | on 'rm -rf ~/.headless/config && mkdir -p -m 0700 ~/.headless/config && tar -xf - -C ~/.headless/config'
flags=""
if [ -n "$SOURCE" ]; then
  tar -C "$SOURCE" --exclude .git -cf - . \
    | on 'rm -rf ~/.headless/source && mkdir -p -m 0700 ~/.headless/source && tar -xf - -C ~/.headless/source'
  flags='--override-input headless path:$HOME/.headless/source --no-write-lock-file'
elif [ ! -f "$CONFIG/flake.lock" ]; then
  on "$NIX flake lock path:\$HOME/.headless/config" || die "nix could not lock the config's inputs"
fi

say "building the system on $ADDRESS"
system="$(on "$NIX build --no-link --print-out-paths $flags path:\$HOME/.headless/config#darwinConfigurations.machine.system" | tail -n 1)" \
  || die "the system did not build; the errors above say why"
[[ "$system" =~ ^/nix/store/[a-z0-9]{32}-darwin-system-[A-Za-z0-9._-]+$ ]] || die "the build gave no system path"

say "switching $ADDRESS to $system"
as_root "/bin/bash ~/.headless/remote/activate.sh $system" || die "the switch failed; the errors above say why"
unset PASSWORD

if [ -z "$SOURCE" ] && [ ! -f "$CONFIG/flake.lock" ]; then
  on 'cat ~/.headless/config/flake.lock' > "$CONFIG/flake.lock"
  say "wrote flake.lock into $CONFIG; commit it"
fi
say "applied"
