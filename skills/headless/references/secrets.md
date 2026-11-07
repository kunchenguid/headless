# Keeping the admin password in a secret store

The skill needs the Mac's admin password for three things: the first SSH
sign-in (before your key is on the Mac), `sudo` during the admin session and
every apply or restart, and the automatic sign-in macOS performs at start-up.
The agent never sees it. It names a store entry; `scripts/secret-run.sh`
reads the entry and hands the password to the step on a pipe (file
descriptor 3), and the step passes it to `sudo -S` or SSH's password prompt.
It never appears on a command line, in an environment variable of the agent,
or in the scripts' output. The scripts write it to one file only: with
automatic sign-in on, the Mac's `/etc/kcpassword`, which macOS needs at
start-up and which keeps it in recoverable form (see "On the Mac" below).

The entry name goes in the config folder's `headless.env` as `PASSWORD_REF`.

## Automic Vault (recommended on a Mac)

[Automic Vault](https://github.com/automic-vault/automic-vault) keeps secrets
in the macOS Data Protection Keychain and asks you to approve each use. It
has no command that prints a secret.

Save the password (you type it; it is not echoed):

```sh
av save HEADLESS_MAC_PASSWORD
```

Entry name: `av:HEADLESS_MAC_PASSWORD`. Each step that needs the password
runs `av inject --mode=fd +HEADLESS_MAC_PASSWORD:3 -- <step>`, and Automic
Vault shows an approval window for that exact command; approve it.

## 1Password

With the [1Password CLI](https://developer.1password.com/docs/cli/) signed
in, save the password as an item (in the app, or
`op item create --category=password --title "Headless Mac"`, then set the
password field in the app). Entry name: the item's secret reference, such as
`op:op://Private/Headless Mac/password`. The helper runs `op read` on it.

## Bitwarden

With the [Bitwarden CLI](https://bitwarden.com/help/cli/) unlocked
(`BW_SESSION` set), save a login item holding the password. Entry name:
`bw:ITEM` (its name or id). The helper runs `bw get password ITEM`.

## Any other store

Any command that prints only the secret works: `cmd:COMMAND`, run with
`sh -c`. For example the macOS login keychain:
`cmd:security find-generic-password -s headless-mac -w`
(save it first with `security add-generic-password -s headless-mac -a admin -w`,
which prompts for the password).

## Last resort: a private env file

When no store is available, the user writes the password into a file only
their account can read, outside the config folder:

```sh
mkdir -p ~/.config/headless && chmod 700 ~/.config/headless
touch ~/.config/headless/mini.env && chmod 600 ~/.config/headless/mini.env
# then, in an editor, add one line:  HEADLESS_PASSWORD=the-password
```

Entry name: `env:~/.config/headless/mini.env:HEADLESS_PASSWORD`. The helper
refuses the file if anyone else can read it, and only ever pipes the value.
The agent must never open the file. The user can make that a rule in the
agent's settings, for example in Claude Code's `~/.claude/settings.json`:

```json
{ "permissions": { "deny": ["Read(~/.config/headless/**)"] } }
```

Be honest about the limit: this is a plain-text file, and an agent or any
program that can run shell commands as the user could still read it. A real
secret store with per-use approval is safer.

## On the Mac: automatic sign-in keeps the password

Whatever the store, automatic sign-in needs macOS to know the password at
start-up, so the Mac keeps it in `/etc/kcpassword`, readable by root only.
That file is not encryption: it holds the password XORed with a fixed key
everyone knows, so anyone who gets root on the Mac, or its disk while
FileVault is off, can recover the password. Tell the user so when they choose
automatic sign-in; with `"autoLogin": false` the file is removed.

## A Tailscale auth key

The same entry formats hold a Tailscale auth key, if the user joins Tailscale
with one; it goes in `headless.env` as `TAILSCALE_KEY_REF` and reaches the
Mac on descriptor 4, then a root-only file that is deleted after the join.
