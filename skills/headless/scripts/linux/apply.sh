#!/bin/bash
# apply.sh - set the Linux machine up from its config folder. The password
# comes from the store each time, for sudo -S on the machine; the machine
# keeps no passwordless admin rule.
#
# usage: apply.sh DIR [--headless-source PATH] [--nixos-branch BRANCH]
#
#   --nixos-branch BRANCH   the nixpkgs branch a machine that already runs
#                           NixOS follows (nixos-26.05, nixos-unstable), when
#                           apply.sh cannot read it on the machine (first run
#                           only)
#   --headless-source PATH  build against this checkout of the headless
#                           flake instead of the one flake.lock pins (NixOS
#                           only; for trying changes to the module itself)
#
# On NixOS it copies the folder to the machine, builds the system there,
# switches to it and keeps the folder in the machine's /etc/nixos (so the
# machine's own updates build the same system). The first run brings the
# machine's own /etc/nixos into the folder (nixos/, imported by system.nix)
# and the template's flake.nix (on the machine's own NixOS release) and
# machine.nix, and copies flake.lock back; commit them.
#
# On any other distribution it applies the distro-neutral script
# (remote/apply-script.sh): key-only SSH, sleep off, automatic updates,
# automatic sign-in (lingering) and Tailscale, as settings.json says.
# shellcheck source=skills/headless/scripts/linux/lib.sh
. "$(dirname "$0")/lib.sh"
load_config "${1-}"
shift
SOURCE="" BRANCH=""
while [ $# -gt 0 ]; do
  case "$1" in
    --headless-source) SOURCE="$(cd "${2:?--headless-source needs a path}" && pwd)"; shift 2 ;;
    --nixos-branch) BRANCH="${2-}"; shift 2 ;;
    *) die "unknown option $1" ;;
  esac
done
need_key
settings_env > /dev/null || exit 1
[ -z "$BRANCH" ] || [[ "$BRANCH" =~ ^nixos-(unstable|[0-9][0-9]\.[0-9][0-9])(-small)?$ ]] \
  || die "--nixos-branch takes a NixOS branch such as nixos-26.05 or nixos-unstable"
set -- "$CONFIG" ${SOURCE:+--headless-source "$SOURCE"} ${BRANCH:+--nixos-branch "$BRANCH"}
with_secrets "$@"
read_password
kind="$(os_kind)"
copy_remote

if [ "$kind" != nixos ]; then
  [ -z "$SOURCE" ] || die "--headless-source is for NixOS machines; $ADDRESS runs $kind"
  put_settings
  say "applying the distro-neutral script on $ADDRESS ($kind)"
  as_root "/usr/bin/env bash ~/.headless/remote/apply-script.sh $LOGIN" || die "the script stopped; the lines above say where"
  unset PASSWORD
  say "applied"
  exit 0
fi

ASSETS="$SCRIPTS/../assets/nixos"
# A folder with its own flake.nix is used as it is (the skill's own, or the
# user's flake exposing nixosConfigurations.machine).
if [ ! -f "$CONFIG/flake.nix" ]; then
  if [ ! -f "$CONFIG/system.nix" ]; then
    # The machine's own configuration stays the base: its boot loader, file
    # systems, users and anything else it already had.
    on 'test ! -e /etc/nixos/HEADLESS.md' \
      || die "/etc/nixos on $ADDRESS is a copy of an earlier headless config folder; copy it into $CONFIG (keeping settings.json and headless.env) and run apply.sh again"
    on 'test ! -e /etc/nixos/flake.nix' \
      || die "/etc/nixos on $ADDRESS is a flake already; follow \"Your own config\" in the skill instead"
    on 'test -f /etc/nixos/configuration.nix' || die "$ADDRESS has no /etc/nixos/configuration.nix to start from"
    mkdir -p "$CONFIG/nixos"
    on 'tar -C /etc/nixos -cf - .' | tar -xf - -C "$CONFIG/nixos" \
      || die "could not copy /etc/nixos from $ADDRESS; a file there is not readable by $LOGIN"
    cat > "$CONFIG/system.nix" <<'NIX'
# The machine's own NixOS configuration, as it was before the headless
# skill (copied from its /etc/nixos into nixos/): its boot loader, file
# systems, users and everything else. Edit it here from now on: apply.sh
# copies this whole folder to the machine's /etc/nixos.
{
  imports = [ ./nixos/configuration.nix ];
}
NIX
    say "copied $ADDRESS's /etc/nixos into $CONFIG/nixos; check it holds nothing private before you push the folder anywhere"
  fi
  [ -e "$CONFIG/machine.nix" ] || cp "$ASSETS/machine.nix" "$CONFIG/machine.nix"
  if grep -q '^  disk = "' "$CONFIG/system.nix"; then
    cp "$ASSETS/flake.nix" "$CONFIG/flake.nix"
  else
    # A machine that already ran NixOS stays on its own release, read on
    # the machine: root's nixos channel, which the version it runs must
    # match (a release such as 26.05.1234.abcdef, or 26.11pre1234.abcdef on
    # unstable). When they disagree or there is no channel, it stops.
    version="$(on 'cat /run/current-system/nixos-version')"
    branch="$BRANCH"
    if [ -z "$branch" ]; then
      channel="$(as_root '/run/current-system/sw/bin/nix-channel --list' | sed -n 's|^nixos [^ ]*/\(nixos-[0-9a-z.-]*\)/*$|\1|p' | head -n 1)"
      case "$channel" in
        nixos-unstable | nixos-unstable-small) [[ "$version" =~ ^[0-9][0-9]\.[0-9][0-9]pre ]] && branch="$channel" ;;
        nixos-[0-9][0-9].[0-9][0-9] | nixos-[0-9][0-9].[0-9][0-9]-small)
          r="${channel#nixos-}"
          r="${r%-small}"
          [[ "$version" == "$r."* ]] && branch="$channel" ;;
      esac
      [ -n "$branch" ] || die "could not tell which NixOS release $ADDRESS follows (it runs $version; root's nixos channel is ${channel:-not set}); run apply.sh again with --nixos-branch and the branch it should stay on, such as nixos-26.05 or nixos-unstable"
    fi
    awk -v branch="$branch" '$0 == "    nixpkgs.url = \"github:NixOS/nixpkgs/nixos-unstable\";" {
        print "    nixpkgs.url = \"github:NixOS/nixpkgs/" branch "\";"
        next
      } { print }' "$ASSETS/flake.nix" > "$CONFIG/flake.nix"
    grep -q "nixpkgs/$branch\"" "$CONFIG/flake.nix" || die "could not write $CONFIG/flake.nix"
    say "$ADDRESS runs NixOS $version; its config follows $branch"
  fi
fi
# install-nixos.sh's disk layout fits only a machine it installed: on any
# other, switching to it would point the boot loader and file systems at
# partitions the machine does not have.
if grep -q '^  disk = "' "$CONFIG/system.nix" 2> /dev/null \
  && ! on 'test "$(readlink -f /dev/disk/by-partlabel/disk-main-root)" = "$(findmnt -n -o SOURCE /)"'; then
  die "$CONFIG/system.nix is the install layout of install-nixos.sh, but $ADDRESS was not installed with it (an install that did not finish?); remove flake.nix, flake.lock, machine.nix, system.nix, hardware-configuration.nix and network.nix from $CONFIG and run apply.sh again"
fi
if command -v git > /dev/null && [ -d "$CONFIG/.git" ]; then git -C "$CONFIG" add -A; fi

say "copying $CONFIG to $ADDRESS"
tar_c -C "$CONFIG" --exclude .git --exclude known_hosts . \
  | on 'rm -rf ~/.headless/config && mkdir -p -m 0700 ~/.headless/config && tar -xf - -C ~/.headless/config'
# The machine's own updates move nixpkgs in /etc/nixos/flake.lock to newer
# revisions of the same branch; once the machine boots a system built from
# the newer one, apply keeps it instead of going back to the folder's, and
# writes it into the folder.
# shellcheck disable=SC2016 # runs on the machine
if [ -f "$CONFIG/flake.lock" ] && [ "$(on 'f="$HOME/.headless/config/flake.lock"
  [ -f /etc/nixos/HEADLESS.md ] && [ -f /etc/nixos/flake.lock ] || exit 0
  rev="$(/nix/var/nix/profiles/system/sw/bin/nixos-version --revision 2> /dev/null)"
  out="$('"$NIXOS_NIX"' eval --raw --impure --expr "import $HOME/.headless/remote/newer-nixpkgs.nix \"$f\" \"/etc/nixos/flake.lock\" \"$rev\"")"
  [ -z "$out" ] || { printf "%s\n" "$out" > "$f" && echo newer; }')" = newer ]; then
  on 'cat ~/.headless/config/flake.lock' > "$CONFIG/flake.lock.new" && mv "$CONFIG/flake.lock.new" "$CONFIG/flake.lock" \
    || die "could not copy the machine's flake.lock into $CONFIG"
  say "kept the newer nixpkgs $ADDRESS updated to by itself; wrote it into $CONFIG/flake.lock, commit it"
fi
if [ -n "$SOURCE" ]; then
  tar_c -C "$SOURCE" --exclude .git . \
    | on 'rm -rf ~/.headless/source && mkdir -p -m 0700 ~/.headless/source && tar -xf - -C ~/.headless/source'
  # The machine's copy is locked to that checkout, so /etc/nixos rebuilds
  # what runs; the folder's own flake.lock stays as it was.
  on "$NIXOS_NIX flake lock --override-input headless path:\$HOME/.headless/source path:\$HOME/.headless/config" \
    || die "nix could not lock the config against $SOURCE"
elif [ ! -f "$CONFIG/flake.lock" ]; then
  on "$NIXOS_NIX flake lock path:\$HOME/.headless/config" || die "nix could not lock the config's inputs"
fi

say "building the system on $ADDRESS"
system="$(on "$NIXOS_NIX build --no-link --print-out-paths path:\$HOME/.headless/config#nixosConfigurations.machine.config.system.build.toplevel" | tail -n 1)" \
  || die "the system did not build; the errors above say why"
[[ "$system" =~ ^/nix/store/[a-z0-9]{32}-nixos-system-[A-Za-z0-9._-]+$ ]] || die "the build gave no system path"

say "switching $ADDRESS to $system"
as_root "/bin/sh ~/.headless/remote/activate.sh $system ~/.headless/config" || die "the switch failed; the errors above say why"
unset PASSWORD

if [ -z "$SOURCE" ] && [ ! -f "$CONFIG/flake.lock" ]; then
  on 'cat ~/.headless/config/flake.lock' > "$CONFIG/flake.lock"
  say "wrote flake.lock into $CONFIG; commit it"
fi
say "applied"
