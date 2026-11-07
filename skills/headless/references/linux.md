# Linux details

## Before the skill starts (at the machine)

- **systemd**, on x86_64 or aarch64. NixOS uses the module; Debian, Ubuntu
  and Fedora (dnf5) use the distro-neutral script. Another distribution can
  use the script with `autoUpdates` and Tailscale off, or be replaced with
  NixOS.
- **An account with a password that may use sudo**: in the `sudo` group
  (Debian, Ubuntu) or `wheel` (Fedora, NixOS). The skill never signs in as
  root and adds no passwordless sudo rule; every admin step pipes the
  password from the store to `sudo -S`.
- **An SSH server** the user can reach with that account's password, for
  the first sign-in only.
- **Its address**: an IP address or a name.

## What the settings do

`settings.json` is the same for NixOS and for the script. On NixOS it sets
the module's options (`modules/nixos/headless.nix`, exported as
`nixosModules.headless`).

| Setting | Default | What it does |
| --- | --- | --- |
| `user` | (required) | The admin account. |
| `hostName` | `null` | The machine's host name; `null` keeps the current one. |
| `sshKeys` | your key | Public keys that may sign in, besides `~/.ssh/authorized_keys`. |
| `keyOnlySsh` | `true` | SSH password, keyboard-interactive and root sign-in off. |
| `autoLogin` | `true` | The account's session starts at boot (systemd lingering), so its user services run with nobody signed in. Nothing signs in on a screen. |
| `tailscale.enable` | `false` | Run the Tailscale daemon (on the script path, from Tailscale's own signed package repository). |
| `extras.neverSleep` | `true` | Sleep, suspend and hibernate are masked. |
| `extras.autoUpdates` | `true` | Script path: unattended-upgrades (apt) or dnf5-automatic applying updates. NixOS: nothing; updates come from the config folder. |

Always on: SSH ends sessions whose other end is gone after about three
minutes, and `/etc/headless/settings.env` records what the machine should
be, for `verify.sh`. On NixOS the account is in `wheel`, sudo asks for its
password, and flakes are on.

The script writes `/etc/ssh/sshd_config.d/00-headless.conf` (first in name
order, so it wins over the distribution's own files), and checks with
`sshd -T` that password sign-in is really off. On Fedora that folder is
root-only, so `verify.sh` reports that line as `n/a` and relies on its
check that the server refuses a password. Turning a setting off later
undoes it: the SSH lines go, lingering stops. Masked sleep targets and
installed packages stay.

## NixOS: the config folder

On a machine that already runs NixOS, the first `apply.sh` copies its
`/etc/nixos` into `nixos/` in the folder and writes `system.nix`, which
imports it; the machine's `/etc/nixos` is no longer used. It may hold
private things (passwords set in `configuration.nix`, Wi-Fi keys); the
user should check before pushing the folder anywhere. If `/etc/nixos` is
already a flake, `apply.sh` stops: add `headless.nixosModules.headless` to
that flake instead and expose it as `nixosConfigurations.machine`.

`apply.sh` builds on the machine (`nix build`) and switches with
`switch-to-configuration`, the same as `nixos-rebuild switch`. If a switch
leaves the machine wrong, `sudo nixos-rebuild switch --rollback` at the
machine goes back one generation, and the boot menu lists older ones.

## Installing NixOS (nixos-anywhere)

`install-nixos.sh` starts the NixOS installer from memory on the running
machine (kexec), then runs nixos-anywhere (pinned) from this computer to
partition the chosen disk with the template's disko layout (GPT, an EFI
partition and an ext4 root, booting with GRUB on both BIOS and EFI),
install, and restart. What carries over:

- the SSH host key, so `known_hosts` keeps working;
- the address: the installer keeps the addresses the machine had, and the
  new system asks DHCP again (a router that hands out addresses by MAC
  gives it the same one);
- the account's password (its hash, in a root-only file the new system
  reads when it makes the account) and the user's key.

What it needs: Nix on this computer, 2 GB of memory on the machine, a
machine that is x86_64 or aarch64, and Secure Boot off (the kernel's
lockdown stops kexec). It refuses a machine that already runs NixOS.

nixos-anywhere signs in to the installer without checking host keys (its
own SSH options win over any passed to it). The script first checks, with
the pinned key, that the installer answers as the same machine before it
starts nixos-anywhere.

If it fails before the disk was erased, restarting the machine brings its
old system back and the script can run again. If it fails after, the disk
holds a half-installed system: install NixOS from a USB stick.

## When something fails

- **"is in neither the wheel nor the sudo group"**: add the account at the machine
  (`usermod -aG sudo NAME`, or `wheel`), sign out and in, and run
  `connect.sh` again.
- **"does not read /etc/ssh/sshd_config.d"**: an old or edited
  `sshd_config`; add `Include /etc/ssh/sshd_config.d/*.conf` at its top.
- **"another setting overrides"**: some file sets `PasswordAuthentication
  yes` before the headless one; find it with `sudo sshd -T` and
  `grep -r PasswordAuthentication /etc/ssh`.
- **The installer did not start**: Secure Boot is on, or the machine's
  kernel has no kexec; turn Secure Boot off, or install NixOS by hand.
- **It does not come back after a restart**: the machine's firmware decides
  whether it powers on after a power cut and whether it wakes from the
  network; set those in its firmware settings. The skill cannot change
  them from Linux.
