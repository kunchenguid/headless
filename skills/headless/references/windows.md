# Windows details

## Before the skill starts (at the PC)

- **Windows 11** (Home or Pro) or **Windows Server 2025**, on an x86_64 or
  Arm64 PC (tested on Windows 11 26H2 and Windows Server 2025).
- **A local administrator account with a password.** Not a Microsoft
  account: automatic sign-in needs a password Windows can check on its own,
  and the skill refuses to store one for another kind of account. A PC set
  up with a Microsoft account can add a local one under Settings > Accounts
  > Other users > Add account > "I don't have this person's sign-in
  information" > "Add a user without a Microsoft account", then make it an
  administrator there.
- **An account name the scripts can carry**: letters, digits, dots, dashes
  and underscores, at most 20, in any case (Windows ignores case, and so
  does the skill). A name with a space or another character, such as
  `Alex Smith`, cannot go safely through SSH and the scripts, and
  `new-config.sh` refuses it. Make another local administrator account
  for the skill instead (Settings > Accounts > Other users > Add account,
  as above, with a name like `headless`), with its own password in the
  store; that account is the one that signs in by itself.
- **OpenSSH Server installed and running**, from step W1's lines in
  Windows PowerShell run as administrator. If `Add-WindowsCapability`
  fails, the PC usually cannot reach Windows Update: check its network, or
  use Settings > System > Optional features > View features > OpenSSH
  Server instead.
- **SSH allowed through Windows Firewall.** Installing OpenSSH Server adds
  the rule `OpenSSH-Server-In-TCP` for TCP port 22. It applies to Private
  networks only (on Windows 11 and on Windows Server 2025), and Windows
  makes every new network Public, so SSH stays blocked until the network is
  marked Private (step W1's last line, or Settings > Network & internet >
  the network > Network profile type > Private). On a network the user
  does not trust, keep it Public and reach the PC some other way; the
  skill does not open SSH on Public networks.
- **Its address**: Settings > Network & internet > (the network) >
  Properties shows the IPv4 address; the PC's name followed by `.local`
  often works too.

## What the settings do

`settings.json` in the config folder:

| Setting | Default | What it does |
| --- | --- | --- |
| `user` | (required) | The admin account the skill signs in as, and the one that signs in by itself. |
| `hostName` | `null` | The computer name, at most 15 letters, digits and dashes; `null` keeps the current one. A new name takes effect at the next restart. |
| `sshKeys` | your key | Public keys that may sign in, in `C:\ProgramData\ssh\administrators_authorized_keys`. |
| `keyOnlySsh` | `true` | Password sign-in over SSH off. |
| `autoLogin` | `true` | The account signs in on the screen by itself at start-up. |
| `tailscale.enable` | `false` | Installs Tailscale to run before anyone signs in. |

Extras, each on by default and each can be turned off with
`--extra-off NAME` (or `false` under `extras`):

| Extra | What it does |
| --- | --- |
| `neverSleep` | Turns hibernation off and sets "sleep after" and "hibernate after" to never, on mains and battery. |
| `powerButtonShutsDown` | Pressing the power button shuts the PC down cleanly (instead of sleeping). |
| `hideSleep` | Removes Sleep from the Start menu's power options. |
| `updatesOvernight` | Sets Windows Update's active hours to 8:00 to 2:00, so update restarts happen between 2:00 and 8:00. |

Always set, whatever the settings: OpenSSH Server starts at start-up, its
shell is Windows PowerShell, and the top of `C:\ProgramData\ssh\sshd_config`
holds a block written by the skill (password sign-in off when `keyOnlySsh`
is on, and sessions whose other end has gone are closed after about three
minutes). `apply.sh` checks the new `sshd_config` with `sshd -t` before
using it and keeps the original as `sshd_config.before-headless`.

**Automatic sign-in.** `apply.sh` checks the password from the store against
the account first and changes nothing if it is wrong. It then sets
Winlogon's `AutoAdminLogon`, `DefaultUserName` and `DefaultDomainName`, and
keeps the password as the LSA secret `DefaultPassword`, the way Microsoft's
Autologon tool does. It is never written as plain text in the registry, and
any plain-text `DefaultPassword` value found there is removed. Any
administrator of the PC can still read the LSA secret back. If "For
improved security, only allow Windows Hello sign-in" is on, `apply.sh`
turns it off, since automatic sign-in needs the password. Turning
`autoLogin` off removes the stored password.

**`machine.ps1`** is yours: `apply.sh` runs it after the headless settings,
as the admin account in its SSH session. Keep it safe to run again.

## Where things go on the PC

- `C:\ProgramData\headless\remote`: the skill's scripts, copied on every run.
- `C:\ProgramData\headless\config`: the config folder, copied on every
  `apply.sh` (without `.git`, `known_hosts` and `headless.env`).
- `C:\ProgramData\headless\settings.json`: the record of what was applied,
  which `verify.sh` reads.
- The whole `C:\ProgramData\headless` folder is readable by Administrators
  and SYSTEM only.

## Tailscale

`apply.sh` downloads Tailscale's own installer (pinned version, checked
SHA-256) and installs it with unattended mode on, so it connects at
start-up before anyone signs in. An existing Tailscale install is kept
and not reinstalled; `apply.sh` sets the same unattended policy on it
(`UnattendedMode` = `always` under `HKLM\SOFTWARE\Policies\Tailscale`),
so it also runs before anyone signs in, as long as the skill's account is
the one that joined it (see "When something fails"). Then `tailscale.sh`
joins as on a Mac (`references/tailscale.md`).

## When something fails

- **`connect.sh`: the machine does not answer on port 22.** OpenSSH
  Server is not running, or the firewall blocks it: the network is Public
  (step W1's last line).
- **`connect.sh`: the password does not work.** Check that OpenSSH Server
  is running (step W1), that the store holds the local account's password
  (not a PIN), and that the account is a local one.
- **`connect.sh`: not an administrator.** The account is a standard one.
  Make it an administrator at the PC (Settings > Accounts > Other users),
  or use another account.
- **`apply.sh`: the password does not sign the account in.** The store
  holds an old password; the user updates it there and runs `apply.sh`
  again. `apply.sh` changed no setting.
- **`restart.sh`: the account did not sign in by itself.** Check the
  password in the store and run `apply.sh` again. A PC joined to a domain,
  or with a sign-in notice set by policy, waits at the sign-in screen.
- **Tailscale: "already in use by" or "running in server mode" for
  another account.** Tailscale on Windows answers only the account that
  joined it to the tailnet, so a Tailscale another account set up before
  the skill cannot be read or joined by the skill's account, even after
  that account logs out of it. Use that account for the skill, or have the
  user uninstall Tailscale at the PC (Settings > Apps) and run `apply.sh`
  and `tailscale.sh` again to install and join it as the skill's account.
- **A changed host key** stops every step on purpose; ask the user whether
  Windows was reinstalled before removing the folder's `known_hosts`.

## Removing it

Set `"autoLogin": false` and run `apply.sh` to remove the stored password.
Then, at the PC, delete `C:\ProgramData\headless`, remove the headless
block from the top of `C:\ProgramData\ssh\sshd_config` (or restore
`sshd_config.before-headless`), and uninstall Tailscale and OpenSSH Server
under Settings > Apps if they are no longer wanted.
