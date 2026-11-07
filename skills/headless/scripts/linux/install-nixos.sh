#!/bin/bash
# install-nixos.sh - replace a Linux machine's system with NixOS and the
# headless module, using nixos-anywhere. This ERASES THE WHOLE DISK named
# with --disk; ask the user first, and only pass --yes-wipe once they agreed.
#
# usage: install-nixos.sh DIR --list-disks
#        install-nixos.sh DIR --disk /dev/DISK --yes-wipe [--headless-source PATH]
#
#   --list-disks            show the machine's disks and stop
#   --disk /dev/DISK        the whole disk to install on (erased)
#   --yes-wipe              the user agreed to erase it
#   --headless-source PATH  build against this checkout of the headless
#                           flake (for trying changes to the module itself)
#
# Needs Nix on this computer (it runs nixos-anywhere) and an x86_64 or
# aarch64 machine with at least 2 GB of memory and Secure Boot off. The
# machine keeps its SSH host key, its address and the admin account's
# password (a fixed address goes into network.nix); the admin's SSH key
# keeps working. DIR gets the NixOS config (flake.nix, machine.nix,
# system.nix, hardware-configuration.nix, network.nix if any, and
# flake.lock); commit it. Run connect.sh first.
# shellcheck source=skills/headless/scripts/linux/lib.sh
. "$(dirname "$0")/lib.sh"
load_config "${1-}"
shift
DISK="" WIPE=0 LIST=0 SOURCE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --disk) DISK="${2-}"; shift 2 ;;
    --yes-wipe) WIPE=1; shift ;;
    --list-disks) LIST=1; shift ;;
    --headless-source) SOURCE="$(cd "${2:?--headless-source needs a path}" && pwd)"; shift 2 ;;
    *) die "unknown option $1" ;;
  esac
done
# nixos-anywhere, pinned.
NIXOS_ANYWHERE=github:nix-community/nixos-anywhere/1.13.0
need_key

kind="$(os_kind)"
[ "$kind" != nixos ] || die "$ADDRESS runs NixOS already; use apply.sh"
if [ "$LIST" = 1 ]; then
  on 'lsblk -d -e 1,7,11 -o NAME,SIZE,MODEL,TYPE'
  on 'findmnt -n -o SOURCE /' | sed 's/^/headless: the running system is on /'
  exit 0
fi

[[ "$DISK" =~ ^/dev/[A-Za-z0-9/_.:-]+$ ]] || die "name the whole disk to install on with --disk (see --list-disks)"
[ "$(on "lsblk -d -n -o TYPE '$DISK'" 2> /dev/null)" = disk ] || die "$DISK is not a whole disk on $ADDRESS (see --list-disks)"
[ "$WIPE" = 1 ] || die "this erases everything on $DISK of $ADDRESS; ask the user, and run again with --yes-wipe only once they agreed"

arch="$(on 'uname -m')"
case "$arch" in x86_64 | aarch64) ;; *) die "nixos-anywhere installs on x86_64 and aarch64 machines, not $arch" ;; esac
mem_kb="$(on "sed -n 's/^MemTotal:[[:space:]]*\([0-9]*\) kB/\1/p' /proc/meminfo")"
[ "${mem_kb:-0}" -ge 1900000 ] || die "$ADDRESS has $((mem_kb / 1024)) MB of memory; the installer needs 2 GB"
lockdown="$(on 'cat /sys/kernel/security/lockdown 2> /dev/null' || true)"
[ -z "$lockdown" ] || [[ "$lockdown" == *"[none]"* ]] \
  || die "$ADDRESS has Secure Boot on (kernel lockdown), which stops the installer from starting; turn Secure Boot off in its firmware settings"
NIX="$(command -v nix || echo /nix/var/nix/profiles/default/bin/nix)"
[ -x "$NIX" ] || die "installing NixOS runs nixos-anywhere, which needs Nix on this computer; install Nix, or keep the distribution and use apply.sh"
NIXF=("$NIX" --extra-experimental-features 'nix-command flakes')
# A folder as a flake reference; a space in it must be written %20.
flake_ref() { printf 'path:%s' "${1// /%20}"; }
settings_env > /dev/null || exit 1

# The NixOS config, with the chosen disk.
ASSETS="$SCRIPTS/../assets/nixos"
for f in flake.nix machine.nix; do
  [ -e "$CONFIG/$f" ] || cp "$ASSETS/$f" "$CONFIG/$f"
done
if [ ! -e "$CONFIG/system.nix" ]; then
  cp "$ASSETS/system.nix" "$CONFIG/system.nix"
fi
grep -q '^  disk = "' "$CONFIG/system.nix" || die "$CONFIG/system.nix is not the install layout (it has no disk line)"
sed -i.bak "s|^  disk = \".*\";|  disk = \"$DISK\";|" "$CONFIG/system.nix" && rm -f "$CONFIG/system.nix.bak"

set -- "$CONFIG" --disk "$DISK" --yes-wipe ${SOURCE:+--headless-source "$SOURCE"}
with_secrets "$@"
read_password

# The address this computer reaches the machine at. One the machine set
# itself (not from DHCP) goes into network.nix, so the new system keeps it;
# a DHCP address comes back from DHCP. Anything else (IPv6, or an address
# on a bridge, bond or VLAN rather than the network card itself) stops here,
# before the disk is touched: the new system might not come back at it.
# shellcheck disable=SC2016 # runs on the machine
net="$(on 'set -- $SSH_CONNECTION; a="$3"
  line="$(ip -4 -o addr show | awk -v a="$a" "{ split(\$4, p, \"/\"); if (p[1] == a) print }" | head -n 1)"
  [ -n "$line" ] || { echo unknown; exit 0; }
  dev="$(printf "%s\n" "$line" | awk "{ print \$2 }")"
  [ -e "/sys/class/net/$dev/device" ] || { echo "virtual $dev"; exit 0; }
  case "$line" in *" dynamic"*) echo dhcp; exit 0 ;; esac
  echo "static $(printf "%s\n" "$line" | awk "{ print \$4 }") $(cat "/sys/class/net/$dev/address")"
  ip -4 route show default dev "$dev" | awk "/^default via/ { print \"gateway \" \$3; exit }"
  r=/etc/resolv.conf; [ ! -r /run/systemd/resolve/resolv.conf ] || r=/run/systemd/resolve/resolv.conf
  awk "/^nameserver [0-9.]+\$/ && \$2 !~ /^127\\./ { print \"dns \" \$2 }" "$r"')" \
  || die "could not read $ADDRESS's network settings"
rm -f "$CONFIG/network.nix"
case "$net" in
  static\ *)
    read -r _ cidr mac <<< "$(printf '%s\n' "$net" | head -n 1)"
    gw="$(printf '%s\n' "$net" | sed -n 's/^gateway //p' | head -n 1)"
    dns="$(printf '%s\n' "$net" | sed -n 's/^dns //p' | sed 's/.*/"&"/' | tr '\n' ' ')"
    [[ "$cidr" =~ ^[0-9.]+/[0-9]+$ ]] && [[ "$mac" =~ ^[0-9a-f:]{17}$ ]] && [[ "$gw" =~ ^[0-9.]*$ ]] \
      || die "could not read $ADDRESS's fixed address ($net)"
    gws=""
    [ -z "$gw" ] || gws="\"$gw\" "
    cat > "$CONFIG/network.nix" <<NIX
# The fixed address this machine had before NixOS was installed (it did not
# come from DHCP), on the network card with this hardware address. Written
# by install-nixos.sh.
{
  networking.useNetworkd = true;
  systemd.network.networks."10-headless-fixed" = {
    matchConfig.MACAddress = "$mac";
    address = [ "$cidr" ];
    gateway = [ $gws];
    dns = [ $dns];
  };
}
NIX
    "${NIXF[@]}" eval --json --file "$CONFIG/network.nix" > /dev/null || die "could not write $CONFIG/network.nix"
    say "$ADDRESS has a fixed address ($cidr${gw:+, gateway $gw}); the new system keeps it (network.nix)" ;;
  dhcp) say "$ADDRESS's address comes from DHCP; the new system asks DHCP again" ;;
  virtual\ *) die "$ADDRESS is on ${net#virtual }, a bridge, bond, VLAN or other virtual network device, which install-nixos.sh does not carry over; nothing was changed. Reach the machine at an IPv4 address on its network card, or install NixOS by hand" ;;
  *) die "could not tell where $ADDRESS's address comes from (install-nixos.sh carries over an IPv4 address on the machine's network card); nothing was changed. Reach the machine at such an address, or install NixOS by hand" ;;
esac
if command -v git > /dev/null && [ -d "$CONFIG/.git" ]; then git -C "$CONFIG" add -A; fi
if [ -n "$SOURCE" ]; then
  "${NIXF[@]}" flake lock --override-input headless "$(flake_ref "$SOURCE")" "$(flake_ref "$CONFIG")" || die "could not lock the config against $SOURCE"
fi

# The account's password carries over: its hash goes to the new system in a
# root-only file (system.nix reads it when it first makes the account).
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/extra/var/lib/headless"
chmod 0700 "$tmp/extra/var/lib/headless"
( umask 077; as_root "getent shadow '$LOGIN'" | cut -d: -f2 > "$tmp/extra/var/lib/headless/password-hash" ) \
  || die "could not read $LOGIN's password hash"
grep -qE '^\$[0-9a-z]+\$' "$tmp/extra/var/lib/headless/password-hash" \
  || die "$LOGIN has no usable password hash on $ADDRESS"

copy_remote
say "starting the NixOS installer on $ADDRESS"
as_root "/usr/bin/env bash ~/.headless/remote/kexec.sh" || die "the installer did not start; nothing on the disk changed"
unset PASSWORD

# The installer answers on the same address with the same host key, and
# lets your key sign in as root.
root_on() { ssh "${SSH_OPTS[@]}" "root@$ADDRESS" "$@"; }
start=$SECONDS
until [ "$(root_on 'hostname' 2> /dev/null)" = nixos-installer ]; do
  [ $((SECONDS - start)) -lt 300 ] || die "the installer did not answer on $ADDRESS within 5 minutes; the disk is unchanged, and restarting the machine brings its old system back"
  sleep 5
done
say "the installer is up; installing NixOS on $DISK"

# nixos-anywhere signs in without checking host keys (its own SSH options
# come first and win); the check above, against the pinned key, is what
# makes sure this is the machine's installer.
"${NIXF[@]}" run "$NIXOS_ANYWHERE" -- \
  --phases disko,install,reboot --copy-host-keys --build-on remote \
  --generate-hardware-config nixos-generate-config "$CONFIG/hardware-configuration.nix" \
  --extra-files "$tmp/extra" --flake "$(flake_ref "$CONFIG")#machine" \
  -i "$SSH_KEY" --target-host "root@$ADDRESS" \
  || die "nixos-anywhere failed (above). Restart the machine: if the install had not yet erased the disk, its old system comes back and install-nixos.sh can run again; otherwise it needs NixOS installed from a USB stick"
if command -v git > /dev/null && [ -d "$CONFIG/.git" ]; then git -C "$CONFIG" add -A; fi

start=$SECONDS
until on 'test -e /etc/headless/settings.env' 2> /dev/null; do
  [ $((SECONDS - start)) -lt 600 ] || die "$ADDRESS did not come back as NixOS within 10 minutes"
  sleep 10
done
say "$ADDRESS runs NixOS now: $(on '. /etc/os-release; echo "$PRETTY_NAME"')"
say "commit the config folder; from now on use apply.sh for changes"
