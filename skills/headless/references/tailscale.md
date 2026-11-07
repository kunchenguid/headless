# Tailscale (optional)

Offer Tailscale; never require it. It lets the user reach the machine from
anywhere without opening ports.

- It runs as the open-source `tailscaled` daemon, started by the Mac's
  nix-darwin system (`"tailscale": { "enable": true }` in `settings.json`),
  with no app and no menu bar item. It starts by itself at every start-up.
- If the Mac already runs the **Tailscale app**, leave it alone: keep
  `tailscale` off. Two Tailscale clients on one Mac fight over the network.
  `apply.sh` and `tailscale.sh` refuse to turn it on when they find
  `/Applications/Tailscale.app`.

## Joining

After `apply.sh` has turned it on, run `scripts/mac/tailscale.sh DIR`. It
joins one of two ways:

1. **Sign-in link** (no setup): the script prints a link. Show it to the
   user; they open it in a browser signed in to their tailnet and approve the
   Mac. Then run `tailscale.sh DIR --wait`, which waits up to ten minutes for
   the Mac to connect.
2. **Auth key**: if the user keeps an auth key in their secret store (made in
   the Tailscale admin console under Settings > Keys), put its entry name in
   `headless.env` as `TAILSCALE_KEY_REF` (or pass `--tailscale-key-ref` to
   `new-config.sh`). The script joins at once.

The Mac joins with its host name. `verify.sh` then checks it is connected.

## On Linux

The same settings and the same two ways to join, with
`scripts/linux/tailscale.sh`. On NixOS the module runs `tailscaled`; on
Debian, Ubuntu and Fedora `apply.sh` installs Tailscale from Tailscale's own
signed package repository and starts it. An existing Tailscale install is
kept as it is.

## On Windows

The same settings and the same two ways to join, with
`scripts/windows/tailscale.sh`. `apply.sh` installs Tailscale from its own
installer (pinned version, checked SHA-256) in unattended mode, so it runs
as a service and connects at start-up before anyone signs in. An existing
Tailscale install is kept and not reinstalled; `apply.sh` sets the same
unattended policy on it (`UnattendedMode` = `always` under
`HKLM\SOFTWARE\Policies\Tailscale`), so it too runs before anyone signs in.
Tailscale on Windows answers only the account that joined it, so this
works when the skill's account set it up; `references/windows.md` says
what to do when another account did.

## Another control server

To use a self-hosted control server such as Headscale, set
`TAILSCALE_LOGIN_SERVER` in `headless.env` (or `--tailscale-login-server`).

## Turning it off

Set `"tailscale": { "enable": false }` and run `apply.sh`. Remove the Mac
from the tailnet in the admin console if it should not come back.
