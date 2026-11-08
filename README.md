<h1 align="center">/headless</h1>

<p align="center">
  <a href="https://agentskills.io"
    ><img
      alt="Agent Skills"
      src="https://img.shields.io/badge/Agent%20Skills-package-blue?style=flat-square"
  /></a>
  <a href="LICENSE"
    ><img
      alt="License"
      src="https://img.shields.io/badge/license-MIT-green?style=flat-square"
  /></a>
  <a href="https://img.shields.io/badge/platform-macOS%20%7C%20Linux%20%7C%20Windows-blue?style=flat-square"
    ><img
      alt="Platform"
      src="https://img.shields.io/badge/platform-macOS%20%7C%20Linux%20%7C%20Windows-blue?style=flat-square"
  /></a>
  <a href="https://x.com/kunchenguid"
    ><img
      alt="X"
      src="https://img.shields.io/badge/X-@kunchenguid-black?style=flat-square"
  /></a>
  <a href="https://discord.gg/Wsy2NpnZDu"
    ><img
      alt="Discord"
      src="https://img.shields.io/discord/1439901831038763092?style=flat-square&label=discord"
  /></a>
</p>

<h3 align="center">What if a new machine set itself up while you watched?</h3>

A Mac mini in a closet, a Linux box under the desk, a Windows PC nobody sits
at. Making one run unattended means a dozen settings at the console - never
sleep, sign in by itself after a restart, SSH keys only - and then, usually,
handing your agent the admin password so it can do the rest.

**headless** is an [Agent Skill](https://agentskills.io) that takes a machine
from "an admin account with a password and remote login on" to a configured
headless machine over SSH, one step at a time: it never sleeps, signs itself
in after a restart, takes SSH keys only, and optionally joins Tailscale. The
admin password stays in your secret store; the agent only ever names the
entry.

- **The password never reaches the agent** - it stays in Automic Vault,
  1Password, Bitwarden, any command, or, as a last resort, a private env file.
  The scripts read it and pipe it on; it never lands on a command line or in a
  log.
- **Mac, Linux and Windows** - Apple silicon Macs with
  [Determinate Nix](https://determinate.systems) and
  [nix-darwin](https://github.com/nix-darwin/nix-darwin); NixOS with this
  repository's NixOS module, any other distribution replaced with NixOS by
  [nixos-anywhere](https://github.com/nix-community/nixos-anywhere) if you
  choose, or Debian, Ubuntu and Fedora kept with a distro-neutral script;
  Windows 11 and Windows Server 2025 with a rerunnable PowerShell script over
  OpenSSH.
- **Every step reruns safely** - each step says what it does, runs, and shows
  its result; the last step reads every setting back, restarts the machine
  and checks it comes back.
- **Proven end to end** - each platform's whole journey runs on a
  GitHub-hosted runner over SSH to itself, and the logs are checked for the
  password.

## Quick Start

```sh
# install (global recommended)
$ npx skills add kunchenguid/headless -g

# in your agent
/headless set up my Mac mini at 192.168.1.20 as a headless machine
```

## What it needs

- **Your computer:** macOS or Linux with bash, ssh and tar (and Nix, only to
  install NixOS on a Linux machine).
- **The machine:** an Apple silicon Mac on a current macOS, an x86_64 or
  aarch64 Linux machine with systemd, or a Windows 11 or Windows Server 2025
  PC - with an admin account that has a password, and remote login on.
- **A secret store** for that password. Tailscale is optional.

## How It Works

For a Mac the skill walks you through seven steps:

```
admin account + password + Remote Login on
      │
      ▼
┌────────────────────┐
│ admin access       │  you, once, at the Mac
└─────────┬──────────┘
          ▼
┌────────────────────┐
│ save the password  │  you, once, in your secret store
└─────────┬──────────┘
          ▼
┌────────────────────┐
│ config folder      │  on your computer, from this repository's default config
└─────────┬──────────┘
          ▼
┌────────────────────┐
│ first SSH sign-in  │  host key pinned · your key added
└─────────┬──────────┘
          ▼
┌────────────────────┐
│ admin session      │  Determinate Nix · FileVault off · automatic sign-in
└─────────┬──────────┘
          ▼
┌────────────────────┐
│ apply              │  the config · Tailscale if you want it
└─────────┬──────────┘
          ▼
┌────────────────────┐
│ verify + restart   │  every setting read back · the Mac comes back
└─────────┬──────────┘
          ▼
  headless Mac
```

A Linux machine takes the same path, without the admin session: after the
first sign-in, a machine on NixOS is applied as it is; on another
distribution you choose between installing NixOS (the whole disk is erased)
and keeping it with the script.

A Windows PC starts with a few lines you paste in an administrator
PowerShell to turn OpenSSH Server on (and, on a home or office network
Windows calls Public, to mark it Private so SSH gets through the firewall).
After the first sign-in, applying the config sets key-only SSH, automatic
sign-in (the password kept as an LSA secret), the extras and Tailscale.

## Usage

| Invoke | Example |
| ------ | ------- |
| Slash | `/headless set up my Mac mini at 192.168.1.20 as a headless machine` |
| Natural language | "update my headless Linux server and check it comes back after a restart" |

The agent should auto-invoke when asked to set up, configure, update or check
a machine you reach only over SSH.

## Package layout

```
skills/headless/
  SKILL.md        # the agent contract: the rules and every step
  references/     # mac.md · linux.md · windows.md · secrets.md · tailscale.md
  scripts/        # mac/ · linux/ · windows/: connect, apply, verify, restart, tailscale
  assets/         # darwin/ · nixos/ · windows/: the default configs the skill copies
modules/
  darwin/headless.nix   # the nix-darwin module, darwinModules.headless
  nixos/headless.nix    # the NixOS module, nixosModules.headless
flake.nix         # the modules, templates.darwin (default) and templates.nixos
tests/            # the secret helper's test and the Mac, Linux and Windows journeys CI runs
```

Ships as an [`npx skills`](https://github.com/vercel-labs/skills) package.

The repository is also a Nix flake, and the modules are the layers the skill
applies. Use them from your own flake:

```nix
inputs.headless.url = "github:kunchenguid/headless";
# in your darwinSystem modules:
headless.darwinModules.headless
{ headless = { user = "admin"; sshKeys = [ "ssh-ed25519 ..." ]; }; }
```

`nixosModules.headless` is used the same way in a `nixosSystem`. The options
are listed in `skills/headless/references/mac.md` and
`skills/headless/references/linux.md`.
`nix flake init -t github:kunchenguid/headless#nixos` (or `#darwin`) gives the
starting config the skill copies, the NixOS one with a disko disk layout for
new installs.

## Development

```sh
# edit the skill
$EDITOR skills/headless/SKILL.md

# smoke-test discovery locally
npx skills add ./ -l

# install from this checkout
npx skills add ./ -g -y

# checks
nix flake check                 # modules and default configs build (this system's)
tests/secret-run.test.sh        # the password is piped, never printed
shellcheck -x tests/*.sh skills/headless/scripts/*.sh skills/headless/scripts/*/*.sh skills/headless/scripts/*/remote/*.sh
```

The `mac` workflow runs the whole journey on a GitHub-hosted Mac, over SSH
to itself. The `linux` workflow runs the distro-neutral script on a
GitHub-hosted Ubuntu runner over SSH to itself, and installs NixOS with
nixos-anywhere on an x86_64 Ubuntu virtual machine there, then applies,
restarts and verifies it. The `windows` workflow checks every PowerShell
file parses, then runs the Windows journey on a GitHub-hosted Windows Server
runner over SSH to itself, from Ubuntu under WSL. Each checks its log never
holds the password.

Pull requests to `main` are raised through
[no-mistakes](https://github.com/kunchenguid/no-mistakes): the
`PR must be raised via no-mistakes` check stays red on a pull request opened
by hand until its branch is pushed through the gate (`git push no-mistakes`),
which writes a pipeline attestation into the pull request's description.
