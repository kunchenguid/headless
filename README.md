# headless

An agent skill that sets up a headless machine over SSH, step by step: from
"an admin account with a password and remote login on" to a configured
machine that never sleeps, signs itself in after a restart, takes SSH keys
only, and optionally joins Tailscale. The agent never sees the admin
password: it stays in your secret store (Automic Vault, 1Password,
Bitwarden, any command, or, as a last resort, a private env file).

This version covers **Apple silicon Macs**, configured with
[Determinate Nix](https://determinate.systems) and
[nix-darwin](https://github.com/nix-darwin/nix-darwin). Linux and Windows
are planned.

## Install the skill

```sh
npx skills add kunchenguid/headless -g
```

Then ask your agent to set up your Mac, for example "set up my Mac mini at
192.168.1.20 as a headless machine". The skill walks you through:

1. Admin access and Remote Login at the Mac (you, once).
2. Saving the admin password in your secret store (you, once).
3. A config folder on your computer, from this repository's default config.
4. The first SSH sign-in: host key pinned, your key added.
5. One admin session: Determinate Nix, automatic sign-in.
6. Applying the config, and Tailscale if you want it.
7. Reading every setting back, restarting, and checking the Mac comes back.

## The repository

- `skills/headless/`: the skill (`SKILL.md`, `references/`, `scripts/`, and
  `assets/darwin`, the default config it copies).
- `modules/darwin/headless.nix`: the nix-darwin module, exported as
  `darwinModules.headless`. Use it from your own flake:

  ```nix
  inputs.headless.url = "github:kunchenguid/headless";
  # in your darwinSystem modules:
  headless.darwinModules.headless
  { headless = { user = "admin"; sshKeys = [ "ssh-ed25519 ..." ]; }; }
  ```

  Its options are listed in `skills/headless/references/mac.md`.
- `templates.darwin` (default): `nix flake init -t github:kunchenguid/headless`
  gives the same starting config the skill copies.
- `tests/`: the secret helper's test and the Mac journey CI runs.

## Checks

```sh
nix flake check                 # module and default config build (aarch64-darwin)
tests/secret-run.test.sh        # the password is piped, never printed
shellcheck -x tests/*.sh skills/headless/scripts/*.sh skills/headless/scripts/mac/*.sh skills/headless/scripts/mac/remote/*.sh
```

The `mac` workflow runs the whole journey on a GitHub-hosted Mac, over SSH
to itself, and checks its log never holds the password.

## License

MIT
