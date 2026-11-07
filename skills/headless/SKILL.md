---
name: headless
description: Set up a headless Mac (Apple silicon) over SSH, step by step, from "an admin account with a password and Remote Login on" to a configured machine with Determinate Nix, a nix-darwin config, key-only SSH, automatic sign-in, never-sleep power settings and optional Tailscale, then restart it and confirm it comes back. Use when the user wants to set up, configure, update or check a headless Mac mini or other Mac they reach only over SSH. The admin password stays in the user's secret store (Automic Vault, 1Password, Bitwarden, any command, or a private env file); you only ever name the store entry.
license: MIT
compatibility: Runs on macOS or Linux with bash, ssh and tar. The machine being set up must be an Apple silicon Mac on a current macOS (tested on macOS 26).
---

# headless

Guide the user through setting up one headless machine over SSH. Go one
step at a time: say what the step does, run it, show its result, and only
then move on. Every step is safe to run again.

This version covers **Macs**. For a Linux or Windows machine, say that the
skill does not cover it yet and stop.

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
time. To update inputs (nixpkgs, nix-darwin, this module):
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

## When something fails

- Read the script's last `headless:` line; it says what failed and what to
  do. `references/mac.md` lists the common cases.
- A changed host key stops every step on purpose. Ask the user whether the
  Mac was reinstalled before removing the folder's `known_hosts`.
- Never work around a failed step by turning on password sign-in, adding a
  sudo rule, or printing the secret.
