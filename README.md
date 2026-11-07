# headless

An agent skill that sets up a headless machine over SSH, step by step: from
"an admin account with a password and remote login on" to a configured
machine that never sleeps, signs itself in after a restart, takes SSH keys
only, and optionally joins Tailscale. The agent never sees the admin
password: it stays in your secret store (Automic Vault, 1Password,
Bitwarden, any command, or, as a last resort, a private env file).

This version covers **Apple silicon Macs**, configured with
[Determinate Nix](https://determinate.systems) and
[nix-darwin](https://github.com/nix-darwin/nix-darwin), and **Linux
machines**: NixOS with this repository's NixOS module; any other
distribution replaced with NixOS by
[nixos-anywhere](https://github.com/nix-community/nixos-anywhere) if you
choose; or, if you keep Debian, Ubuntu or Fedora, a distro-neutral script;
and **Windows 11 and Windows Server 2025** PCs, configured with a
rerunnable PowerShell script over OpenSSH.

## Install the skill

```sh
npx skills add kunchenguid/headless -g
```

Then ask your agent to set up your machine, for example "set up my Mac mini
at 192.168.1.20 as a headless machine". For a Mac the skill walks you
through:

1. Admin access and Remote Login at the Mac (you, once).
2. Saving the admin password in your secret store (you, once).
3. A config folder on your computer, from this repository's default config.
4. The first SSH sign-in: host key pinned, your key added.
5. One admin session: Determinate Nix, automatic sign-in.
6. Applying the config, and Tailscale if you want it.
7. Reading every setting back, restarting, and checking the Mac comes back.

A Linux machine takes the same path, without the admin session: after the
first sign-in, a machine on NixOS is applied as it is; on another
distribution you choose between installing NixOS (the whole disk is erased)
and keeping it with the script. A Windows PC starts with three lines you
paste in an administrator PowerShell to turn OpenSSH Server on; after the
first sign-in, applying the config sets key-only SSH, automatic sign-in
(the password kept as an LSA secret), the extras and Tailscale.

## The repository

- `skills/headless/`: the skill (`SKILL.md`, `references/`, `scripts/`, and
  `assets/darwin`, `assets/nixos` and `assets/windows`, the default
  configs it copies).
- `modules/darwin/headless.nix`: the nix-darwin module, exported as
  `darwinModules.headless`. Use it from your own flake:

  ```nix
  inputs.headless.url = "github:kunchenguid/headless";
  # in your darwinSystem modules:
  headless.darwinModules.headless
  { headless = { user = "admin"; sshKeys = [ "ssh-ed25519 ..." ]; }; }
  ```

  Its options are listed in `skills/headless/references/mac.md`.
- `modules/nixos/headless.nix`: the NixOS module, exported as
  `nixosModules.headless`, used the same way in a `nixosSystem`. Its
  options are listed in `skills/headless/references/linux.md`.
- `templates.darwin` (default) and `templates.nixos`:
  `nix flake init -t github:kunchenguid/headless#nixos` gives the starting
  config the skill copies (with a disko disk layout for new installs).
- `tests/`: the secret helper's test and the Mac, Linux and Windows journeys
  CI runs.

## Checks

```sh
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

## License

MIT
