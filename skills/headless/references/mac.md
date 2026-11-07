# Mac details

## Before the skill starts (at the Mac)

- **Apple silicon, a current macOS** (tested on macOS 26). Intel Macs are
  not supported.
- **An administrator account with a password.** The skill signs in as this
  account, and it is the account that signs in by itself at start-up.
- **Remote Login on**: System Settings > General > Sharing > Remote Login.
  "Allow access for" must include the account.
- **FileVault off**, if the user wants automatic sign-in: System Settings >
  Privacy & Security > FileVault. With FileVault on, macOS waits at its
  unlock screen after every start-up and nobody is there to type the
  password; automatic sign-in cannot get past it. The user can keep
  FileVault on and set `"autoLogin": false`; after a restart the Mac then
  waits at FileVault's unlock screen until someone types the password there,
  and may not answer over SSH until then.
- **Its address**: shown under System Settings > General > Sharing, such as
  `mac-mini.local`, or an IP address from the router.

## What the headless module sets

The config folder's `settings.json` holds the module's options
(`modules/darwin/headless.nix` in this repository):

| Option | Default | What it does |
| --- | --- | --- |
| `user` | (required) | The admin account; nix-darwin's primary user. |
| `hostName` | `null` | Computer, local and host name; `null` keeps the current one. |
| `sshKeys` | your key | Public keys that may sign in, besides `~/.ssh/authorized_keys`. |
| `keyOnlySsh` | `true` | SSH password, keyboard-interactive and root sign-in off. |
| `autoLogin` | `true` | Sign the account in on the screen at every start; `false` removes the stored password. |
| `tailscale.enable` | `false` | Run the open-source Tailscale daemon. |
| `extras.neverSleep` | `true` | The Mac and its disks never sleep; the display sleeps after 10 minutes. |
| `extras.startAfterPowerLoss` | `true` | Start up after a power cut; where the Mac also offers it, after a clean shutdown too. |
| `extras.wakeOnLan` | `true` | Wake for network access. |
| `extras.powerNapOff` | `true` | Power Nap off. |
| `extras.spotlightOff` | `true` | Spotlight indexing off on every volume. |
| `extras.siriOff` | `true` | Siri off for the account. |

Always on: Nix is left to Determinate Nix; nix-darwin's `/Applications/Nix
Apps` step is dropped (it needs a permission nobody can grant over SSH);
SSH ends sessions whose other end is gone after about three minutes; and
`/etc/headless/settings.json` records what the Mac should be, for
`verify.sh`.

Turning an extra off stops the module managing it; it does not put the
macOS default back. Automatic sign-in is the exception: `false` removes the
stored password.

Some Macs, virtual Macs among them, have no start-up-after-power-loss or
wake-for-network setting. The module skips those with a warning, and
`verify.sh` reports them as `n/a`.

Add anything else (packages, more defaults, launchd services) to
`machine.nix` as ordinary nix-darwin options.

## Where things go on the Mac

- `~/.headless/config`: the copy of the config folder each apply builds.
- `~/.headless/remote`: the step scripts each step copies over.
- `/etc/kcpassword`: the automatic sign-in password, root-only, as macOS
  keeps it. The admin step writes it from standard input, never a command
  line (`sysadminctl -autologin` would take it on its command line).
- `/etc/ssh/sshd_config.d/000-headless.conf`: the key-only lines. sshd takes
  the first value it reads, so it is named to come before macOS's own
  `100-macos.conf`.
- `/etc/*.before-nix-darwin`: shell files the Nix installer had edited,
  moved aside before the first switch so nix-darwin can own them.

## Common failures

| Message | Meaning and fix |
| --- | --- |
| `gave no single ed25519 host key; is Remote Login on?` | Remote Login is off, or the address is wrong. |
| `shows a different host key than the one pinned` | The Mac was reinstalled, or something else answers at that address. Find out which before deleting `known_hosts`. |
| `password sign-in ... failed` | Wrong password in the store, or the account is not allowed under Remote Login. |
| `is not an administrator` | Use an admin account, or make this one an admin at the Mac. |
| `FileVault is on` | Turn FileVault off, or set `"autoLogin": false`. |
| `the system did not build` | An error in `machine.nix` or `settings.json`; the Nix error above names the line. |
| `did not come back within ... seconds` | The Mac did not answer after the restart. Check it at its screen; with FileVault on it waits for its password. |
| `is not signed in on the screen after the restart` | Automatic sign-in did not work: FileVault on, or the password changed since `admin.sh` stored it (run it again). |

## Removing it

`sudo /run/current-system/sw/bin/darwin-uninstaller` removes nix-darwin;
Determinate Nix has `/nix/nix-installer uninstall`. Move the
`.before-nix-darwin` files back, delete
`/etc/ssh/sshd_config.d/000-headless.conf`, and remove `/etc/kcpassword`.
