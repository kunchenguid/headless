---
name: headless
description: Set up a headless Mac (Apple silicon) or Linux machine over SSH, step by step, from "an admin account with a password and SSH on" to a configured machine with key-only SSH, automatic sign-in, never-sleep settings and optional Tailscale - on a Mac with Determinate Nix and nix-darwin, on Linux with a NixOS module (installing NixOS with nixos-anywhere if the user wants) or a distro-neutral script for Debian, Ubuntu and Fedora - then restart it and confirm it comes back. Use when the user wants to set up, configure, update or check a headless Mac mini, Linux server or other machine they reach only over SSH. The admin password stays in the user's secret store (Automic Vault, 1Password, Bitwarden, any command, or a private env file); you only ever name the store entry.
license: MIT
compatibility: Runs on macOS or Linux with bash, ssh and tar (and Nix, only to install NixOS on a Linux machine). The machine being set up is an Apple silicon Mac on a current macOS (tested on macOS 26), or an x86_64 or aarch64 Linux machine with systemd running NixOS, Debian, Ubuntu or Fedora.
---

# headless

Guide the user through setting up one headless machine over SSH. Go one
step at a time: say what the step does, run it, show its result, and only
then move on. Every step is safe to run again.

This version covers **Macs** (steps 1 to 7) and **Linux machines** ("Linux
machines" below; steps 2 and the rules are shared). For a Windows machine,
say that the skill does not cover it yet and stop.

All scripts live in this skill's `scripts/` folder; call them by path.
`$SKILL` below means this skill's folder.

## Rules that never bend

- **Never see the password.** Do not ask the user to type it to you, paste
  it, or put it in a file you read. Never run a command that prints a
  secret (`op read`, `bw get`, `cat` on the env file, `secret-run.sh ... --
  cat`, `echo $...`). You only handle the store *entry name*, such as
  `av:HEADLESS_MAC_PASSWORD`. The scripts read the secret themselves and
  pipe it to `sudo -S` or SSH; it never reaches a command line or a log.
- **Never weaken sudo.** Do not add a passwordless sudo rule. Every later
  admin step reads the password from the store again.
- **Key before key-only.** Password sign-in turns off only after
  `connect.sh` has proved the user's key works.
- **Ask before anything the user did not choose**, and stop and ask when a
  step fails in a way its message does not explain.

## Step 1: Admin access at the Mac (the user does this)

Ask the user to confirm, at the Mac itself (screen and keyboard, or screen
sharing), that:

1. It has an **administrator account with a password**. Note its account
   name (short name, such as `admin`).
2. **Remote Login is on** for that account: System Settings > General >
   Sharing > Remote Login (and "Allow full disk access for remote users"
   may stay off).
3. They know its **address**: an IP address or a name such as
   `mac-mini.local` (System Settings > General > Sharing shows it).
4. **FileVault** is off if they want automatic sign-in (step 5 explains).
   System Settings > Privacy & Security > FileVault.

Details and screenshots-free wording for each: `references/mac.md`.

## Step 2: The password goes in a secret store (the user does this)

Ask which secret store they use, recommend one, and have **them** save the
admin password there. Read `references/secrets.md` for each store's exact
save command and the entry name format. In order of preference:

| Store | Entry name you keep |
| --- | --- |
| Automic Vault (macOS) | `av:NAME` |
| 1Password CLI | `op:op://Vault/Item/password` |
| Bitwarden CLI | `bw:ITEM` |
| Any command that prints it | `cmd:COMMAND` |
| Last resort: a private env file | `env:~/.config/headless/NAME.env:HEADLESS_PASSWORD` |

For the env file, tell the user plainly: it is a plain-text file only their
account can read; you will not open it, and they can add a rule to your
settings that denies reading it (`references/secrets.md`), but a program
running as them could still read it. Prefer a real store.

Also make sure the user has an SSH key on this computer
(`~/.ssh/id_ed25519.pub`). If not, offer to make one with
`ssh-keygen -t ed25519` (the user chooses its passphrase). The scripts sign
in without prompts, so a key with a passphrase must be loaded in ssh-agent:
ask the user to run `ssh-add ~/.ssh/id_ed25519` (on a Mac,
`ssh-add --apple-use-keychain ~/.ssh/id_ed25519` keeps it across restarts).

## Step 3: The config folder

Ask where the machine's config should live. Default:
`~/headless/<machine-name>`, a git folder on this computer that is copied to
the Mac on every update; the user can push it to any git host later. If they
already keep a nix-darwin config elsewhere, see "Your own config" below.

Ask these choices, with the defaults in **bold**:

- Machine name (host name): **keep the current one**, or a new one.
- Automatic sign-in at start-up: **on** (needs FileVault off).
- Tailscale: **off**. Offer it; never require it (step 6). If the Mac already
  has the Tailscale app (`/Applications/Tailscale.app`), keep this off and
  leave the app as it is; `apply.sh` refuses to start a second Tailscale.
- Extras, each **on** and each can be turned off: `neverSleep`,
  `startAfterPowerLoss`, `wakeOnLan`, `powerNapOff`, `spotlightOff`,
  `siriOff` (`references/mac.md` says what each does).

Then make the folder:

```sh
$SKILL/scripts/mac/new-config.sh ~/headless/mini \
  --address ADDRESS --login ACCOUNT --password-ref ENTRY \
  [--ssh-key ~/.ssh/id_ed25519] [--host-name NAME] [--no-auto-login] \
  [--tailscale] [--tailscale-key-ref ENTRY] [--extra-off NAME]...
```

It writes `flake.nix`, `machine.nix` (the user's own additions go here),
`settings.json` and `headless.env` (address, account, key and store entry;
no secret). Show the user `settings.json`.

## Step 4: First sign-in

```sh
$SKILL/scripts/mac/connect.sh ~/headless/mini
```

It pins the Mac's SSH host key in the folder's `known_hosts` and prints its
fingerprint; offer the user the command to compare it at the Mac. Then it
signs in once with the password from the store, adds the user's public key,
and checks key sign-in works. With Automic Vault the user approves the
request in its window; tell them to expect it.

## Step 5: The admin session

```sh
$SKILL/scripts/mac/admin.sh ~/headless/mini
```

It installs Determinate Nix (pinned version, checked hash) and, when
automatic sign-in is on, stores the sign-in password macOS uses at start-up
(`/etc/kcpassword`, root-only, and recoverable by anyone with root on the
Mac; say so). If FileVault is on and automatic sign-in is
chosen, it stops and says so: the user either turns FileVault off at the Mac
or sets `"autoLogin": false` in `settings.json`.

## Step 6: Apply the config

```sh
$SKILL/scripts/mac/apply.sh ~/headless/mini
```

It copies the folder to the Mac, builds the system there, and switches to it
with `sudo -S` (password from the store again). The first run copies
`flake.lock` back into the folder. Then commit the folder:
`git -C ~/headless/mini add -A && git -C ~/headless/mini commit -m "headless: set up"`.

**Tailscale (only if chosen).** With `"tailscale": { "enable": true }`
applied:

```sh
$SKILL/scripts/mac/tailscale.sh ~/headless/mini
```

With `TAILSCALE_KEY_REF` set (an auth key in the store) it joins at once.
Otherwise it prints a sign-in link: show it to the user, ask them to open it
and approve the Mac, then run `tailscale.sh ~/headless/mini --wait`. Details:
`references/tailscale.md`.

## Step 7: Verify, restart, verify

```sh
$SKILL/scripts/mac/verify.sh ~/headless/mini
$SKILL/scripts/mac/restart.sh ~/headless/mini
$SKILL/scripts/mac/verify.sh ~/headless/mini
```

`verify.sh` reads every setting back (one `ok` or `FAIL` line each, `n/a`
for a power setting this Mac does not have) and checks that password sign-in
is refused. `restart.sh` restarts the Mac, waits until it answers again with
a new boot time, and, with automatic sign-in on, until the account is signed
in on the screen. Tell the user before restarting.

Finish with a short summary: what is on, what is off, where the config
folder is, and how to update (below).

## Later: updates

Edit `machine.nix` or `settings.json` in the config folder, then run
`apply.sh` and `verify.sh` again. The password is read from the store each
time. Turning an extra off later only stops the config managing it: the
Mac keeps the value the extra set (for example, Spotlight stays off) and
macOS's default does not come back. Tell the user so, and change that
setting at the Mac, or add it to `machine.nix`, if they want it back.
To update inputs (nixpkgs, nix-darwin, this module):
`nix flake update --flake ~/headless/mini` on a computer with Nix, or delete
`flake.lock` and run `apply.sh`.

## Your own config

The config folder is an ordinary nix-darwin flake whose
`darwinConfigurations.machine` imports `headless.darwinModules.headless`.
A user with an existing nix-darwin flake can instead add this repository as
an input, import the module in their own host, set `headless.*` options, and
expose the host as `darwinConfigurations.machine` in a folder these scripts
copy; the scripts only need `headless.env` and that output name. See
`references/mac.md` for the module's options.

On NixOS it works the same way: the folder's `flake.nix` exposes
`nixosConfigurations.machine`, which imports
`headless.nixosModules.headless` and sets `headless.*`
(`references/linux.md` lists the options). A folder with its own
`flake.nix` is used as it is: `apply.sh` copies and builds it and brings
nothing in from `/etc/nixos`. Keep `settings.json` (from `new-config.sh`)
beside it: `apply.sh` checks it and `verify.sh` reads the machine's own
record. Expose the host under its host name too if `nixos-rebuild switch`
at the machine should find it without `--flake /etc/nixos#machine`.

## When something fails

- Read the script's last `headless:` line; it says what failed and what to
  do. `references/mac.md` lists the common cases.
- A changed host key stops every step on purpose. Ask the user whether the
  Mac was reinstalled before removing the folder's `known_hosts`.
- Never work around a failed step by turning on password sign-in, adding a
  sudo rule, or printing the secret.

## Linux machines

The same rules hold. The scripts are in `scripts/linux/`; details, options
and failure cases are in `references/linux.md`.

**L1. Admin access (the user does this).** Ask the user to confirm the
machine runs an **SSH server** they can reach, has an **account with a
password** that may use `sudo` (in the `sudo` or `wheel` group), and its
**address**. Root is not used as the login.

**L2. The password store and key:** step 2 above, unchanged.

**L3. The config folder.** Same questions as step 3, with Linux's extras:
`neverSleep` and `autoUpdates`, each **on**. Automatic sign-in on Linux
means the account's own session (its user services) starts at boot without
anyone signing in; nothing signs in on a screen.

```sh
$SKILL/scripts/linux/new-config.sh ~/headless/box \
  --address ADDRESS --login ACCOUNT --password-ref ENTRY \
  [--ssh-key ~/.ssh/id_ed25519] [--host-name NAME] [--no-auto-login] \
  [--tailscale] [--tailscale-key-ref ENTRY] [--extra-off NAME]...
```

**L4. First sign-in.** `$SKILL/scripts/linux/connect.sh ~/headless/box`,
as in step 4. Its last lines say which distribution the machine runs and
what comes next.

**L5. NixOS, or not.**

- **It runs NixOS:** go to L6. The first `apply.sh` copies the machine's own
  `/etc/nixos` into the folder (`nixos/`), so its boot loader, disks and
  other settings stay, and the machine stays on the NixOS release it runs
  (such as 26.05, read from root's channel). If `apply.sh` cannot tell the
  release, it stops; ask the user which one and pass `--nixos-branch
  nixos-26.05` (or `nixos-unstable`). Ask the user to check that copy holds
  nothing private before they push the folder anywhere. From then on each
  `apply.sh` puts the folder in `/etc/nixos` (the old one is kept as
  `/etc/nixos.before-headless`), so `nixos-rebuild switch` and automatic
  updates at the machine build the same setup; an automatic update takes
  the newest nixpkgs of the machine's release, and once the machine boots a
  system built from it, `apply.sh` keeps that newer one and writes it into
  the folder's `flake.lock` to commit.
- **Any other distribution:** offer to **replace it with NixOS**, using
  nixos-anywhere. Say plainly: this **erases the whole disk**, everything on
  it is gone, and it needs Nix on this computer, an x86_64 or aarch64
  machine with 2 GB of memory and Secure Boot off. The machine keeps its
  address (a fixed one is written into the new setup), SSH host key and the
  account's password; it needs the machine reached at an IPv4 address on
  its wired network card, and stops, changing nothing, otherwise. If the
  user agrees:

  ```sh
  $SKILL/scripts/linux/install-nixos.sh ~/headless/box --list-disks
  $SKILL/scripts/linux/install-nixos.sh ~/headless/box --disk /dev/DISK --yes-wipe
  ```

  Show the disk list and have the user name the disk; pass `--yes-wipe`
  only after they agreed to erase that disk. It takes 5 to 20 minutes.
- **The user keeps their distribution** (Debian, Ubuntu or Fedora): go to
  L6; `apply.sh` runs the distro-neutral script instead.

**L6. Apply, then verify, restart, verify.**

```sh
$SKILL/scripts/linux/apply.sh ~/headless/box
$SKILL/scripts/linux/verify.sh ~/headless/box
$SKILL/scripts/linux/restart.sh ~/headless/box
$SKILL/scripts/linux/verify.sh ~/headless/box
```

On NixOS `apply.sh` builds the system on the machine and switches to it; on
another distribution it runs the script, which prints one `changed:` line
per change and none when run again. Commit the folder afterwards. For
Tailscale, run `$SKILL/scripts/linux/tailscale.sh ~/headless/box` as in
step 6. `restart.sh` restarts the machine, waits for a new boot, and with
automatic sign-in on checks the session started before anyone signed in.
Tell the user before restarting.

Updates: edit `settings.json` (or `machine.nix` on NixOS) and run `apply.sh`
and `verify.sh` again. Other distributions install updates by themselves
(`autoUpdates`). On NixOS, delete `flake.lock` and run `apply.sh` to move
to newer inputs on the same release.
