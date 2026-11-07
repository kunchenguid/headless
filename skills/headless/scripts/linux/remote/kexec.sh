#!/bin/bash
# remote/kexec.sh - start the NixOS installer in memory on a Linux machine
# (kexec), run as root by install-nixos.sh with sudo -S. Nothing on the disk
# changes yet; the installer keeps the machine's SSH host keys, its address
# and the admin's SSH keys, and lets that key sign in as root.
#
# usage: sudo -S bash kexec.sh
set -euo pipefail
exec < /dev/null
die() { echo "headless: $*" >&2; exit 1; }
say() { echo "headless: $*"; }
[ "$(id -u)" -eq 0 ] || die "run kexec.sh as root"
[ -n "${SUDO_USER-}" ] || die "run kexec.sh with sudo, so the installer takes your SSH keys"
export HOME=/root

# The NixOS installer from nix-community/nixos-images, pinned by release and
# hash.
RELEASE=https://github.com/nix-community/nixos-images/releases/download/nixos-26.05
case "$(uname -m)" in
  x86_64)
    URL="$RELEASE/nixos-kexec-installer-noninteractive-x86_64-linux.tar.gz"
    SHA256=6accdc47af6fe9e3c2f1b18035cdee87d58c87c05f130e2fe63134b4884216bc ;;
  aarch64)
    URL="$RELEASE/nixos-kexec-installer-noninteractive-aarch64-linux.tar.gz"
    SHA256=ead5a02f5a440354a3fe5576476817fb6dd9b2477efe5354bf0a62a5510b951c ;;
  *) die "the NixOS installer runs on x86_64 and aarch64, not $(uname -m)" ;;
esac

dir=/root/headless-kexec
rm -rf "$dir"
mkdir -m 0700 "$dir"
cd "$dir"
say "downloading the NixOS installer (about 500 MB)"
if command -v curl > /dev/null; then
  curl -fsSL --retry 3 -o installer.tar.gz "$URL"
elif command -v wget > /dev/null; then
  wget -q -O installer.tar.gz "$URL"
else
  die "the machine has neither curl nor wget to download the installer"
fi
echo "$SHA256  installer.tar.gz" | sha256sum -c - > /dev/null || die "the installer's hash does not match"
tar -xzf installer.tar.gz
rm -f installer.tar.gz

# The installer brings the network up as the machine had it, but asks DHCP
# for addresses the machine got from DHCP, and a DHCP server may hand it a
# new one. Marking them fixed keeps the address the skill reaches it at.
mv kexec/ip kexec/ip.real
cat > kexec/ip <<'SH'
#!/bin/sh
"$(dirname "$0")/ip.real" "$@" | sed -e 's/"dynamic":true/"dynamic":false/g' -e 's/"protocol":"dhcp"/"protocol":"static"/g'
SH
chmod 0755 kexec/ip

say "starting the NixOS installer in memory; the machine goes away for about a minute"
if ! TMPDIR="$dir" setsid --wait "$dir/kexec/run" > run.log 2>&1 || ! grep -q 'machine will boot into nixos' run.log; then
  # Some virtual machines' kernels (Apple's Virtualization framework among
  # them) refuse kexec's newer system call; the older one works there.
  TMPDIR="$dir" setsid --wait "$dir/kexec/run" --kexec-extra-flags --kexec-syscall > run.log 2>&1 || true
  grep -q 'machine will boot into nixos' run.log || { tail -n 30 run.log >&2; die "kexec failed; is Secure Boot on? The installer cannot start with it"; }
fi
say "the installer starts in a few seconds"
