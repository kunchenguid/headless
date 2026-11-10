# Mac details

## Before the skill starts (at the Mac)

- **Apple silicon, a current macOS** (tested on macOS 26). Intel Macs are
  not supported.
- **An administrator account with a password.** The skill signs in as this
  account, and it is the account that signs in by itself at start-up.
- **Remote Login on**: System Settings > General > Sharing > Remote Login.
  "Allow access for" must include the account.
- **FileVault** may be on. With FileVault on, macOS waits at its unlock
  screen after every start-up and nobody is there to type the password;
  automatic sign-in cannot get past it. So with automatic sign-in chosen,
  the admin step turns FileVault off itself (below). The user can instead
  keep FileVault on and set `"autoLogin": false`; after a restart the Mac
  then waits at FileVault's unlock screen, where SSH answers but signs in
  only with the password (key sign-in is refused) until it is unlocked.
- **Its address**: shown under System Settings > General > Sharing, such as
  `mac-mini.local`, or an IP address from the router.

## What the headless module sets

The config folder's `settings.json` holds the module's options
(`modules/darwin/headless.nix` in this repository):

| Option | Default | What it does |
| --- | --- | --- |
| `user` | (required) | The admin account; nix-darwin's primary user. Begin with a lowercase letter, digit or underscore (so a digit is valid); remaining characters may also be dashes. |
| `hostName` | `null` | Computer, local and host name; `null` keeps the current one. |
| `sshKeys` | your key | Public keys that may sign in, besides `~/.ssh/authorized_keys`. |
| `keyOnlySsh` | `true` | SSH password, keyboard-interactive and root sign-in off. |
| `autoLogin` | `true` | Sign the account in on the screen at every start; `false` removes the stored password. |
| `tailscale.enable` | `false` | Run the open-source Tailscale daemon. |
| `extras.neverSleep` | `true` | The Mac and its disks never sleep; the display sleeps after 10 minutes. |
| `extras.startAfterPowerLoss` | `true` | Start up by itself when power comes back after a power cut. |
| `extras.wakeOnLan` | `true` | Wake for network access. |
| `extras.powerNapOff` | `true` | Power Nap off. |
| `extras.spotlightOff` | `true` | Spotlight indexing off on every volume. |
| `extras.siriOff` | `true` | Siri off for the account. |

Always on: Nix is left to Determinate Nix; nix-darwin's `/Applications/Nix
Apps` step is dropped (it needs a permission nobody can grant over SSH);
SSH ends sessions whose other end is gone after about three minutes; and
`/etc/headless/settings.json` records what the Mac should be, for
`verify.sh`.

Turning an extra off later stops the module managing it; it does not put
the macOS default back. The Mac keeps the value the extra set (Spotlight
stays off, the Mac still never sleeps, and so on) until the user changes it
at the Mac or sets it in `machine.nix`. Automatic sign-in is the exception:
`false` removes the stored password.

Some Macs, virtual Macs among them, have no start-up-after-power-loss or
wake-for-network setting. The module skips those with a warning, and
`verify.sh` reports them as `n/a`.

After a restart with automatic sign-in, macOS may show a dialog asking for
a password to unlock the disk "Nix Store", even though Determinate Nix has
already mounted `/nix` and Nix works. This is how macOS and Determinate
Nix behave together, not a failure; nothing waits on the dialog, and
Cancel closes it.

Add anything else (packages, more defaults, launchd services) to
`machine.nix` as ordinary nix-darwin options.

## How the admin step turns FileVault off

With automatic sign-in chosen and FileVault on, `admin.sh`, after installing
Nix, runs, as root, `fdesetup disable -inputplist` with the account name and
password in a plist on standard input (never a command line). In order:

1. While FileVault is still encrypting, it waits: macOS refuses to turn it
   off before then.
2. If the account is not one `fdesetup list` names (it has no secure token,
   macOS's mark that its password can unlock the disk), it asks the user.
   The account made when the Mac was set up has one; an admin made from the
   command line may not.
3. It turns FileVault off, then reads `fdesetup status`: `fdesetup` exits 0
   on most refusals. Anything but "Decryption in progress" or "FileVault is
   Off" asks the user with macOS's message; a managed Mac whose organization
   forbids turning FileVault off ("due to managed preferences") asks too. A
   managed Mac that allows it is treated like any Mac.
4. It waits until decryption ends and FileVault reports off. A restart
   before then stops at FileVault's unlock screen. On virtual Macs,
   decrypting took from 1.5 to 10 minutes; on Apple silicon hardware the
   disk stays hardware-encrypted, so it should be quicker.

Every "ask the user" line names what the user can do: turn FileVault off at
the Mac, or set `"autoLogin": false`. Running `admin.sh` again picks up
where it stopped, including a decryption already under way. Turning off
this way is not in `fdesetup`'s manual (it documents `-inputplist` for
turning on), so a later macOS could change it; the ask is the fallback.
Nix goes in first because, right after FileVault decrypted, macOS could not
mount the Nix store's new encrypted volume until a restart.
An organization's device management can turn FileVault back on later;
`verify.sh` then reports it.

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
| `ask the user: ... FileVault ...` | The admin step could not turn FileVault off; the line says why. The user turns it off at the Mac, or sets `"autoLogin": false`. |
| `FAIL  FileVault off` | FileVault came back on (often the organization managing the Mac); run `admin.sh` again. |
| `the system did not build` | An error in `machine.nix` or `settings.json`; the Nix error above names the line. |
| `did not come back within ... seconds` | The Mac did not answer after the restart. Check it at its screen; with FileVault on it waits at its unlock screen for the password. |
| `is not signed in on the screen after the restart` | Automatic sign-in did not work: FileVault on, or the password changed since `admin.sh` stored it (run it again). |

## Removing it

`sudo /run/current-system/sw/bin/darwin-uninstaller` removes nix-darwin;
Determinate Nix has `/nix/nix-installer uninstall`. Move the
`.before-nix-darwin` files back, delete
`/etc/ssh/sshd_config.d/000-headless.conf`, and remove `/etc/kcpassword`.
