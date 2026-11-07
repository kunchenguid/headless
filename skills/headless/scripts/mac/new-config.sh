#!/bin/bash
# new-config.sh - make a Mac's config folder on this computer from the
# skill's default config (assets/darwin), or update the settings of one.
#
# usage: new-config.sh DIR --address ADDRESS --login LOGIN --password-ref REF
#          [--ssh-key PATH] [--host-name NAME] [--no-auto-login]
#          [--tailscale] [--tailscale-key-ref REF] [--tailscale-login-server URL]
#          [--extra-off NAME]... [--keep-password-ssh]
#
# DIR becomes a git folder holding flake.nix, machine.nix (yours to extend),
# settings.json (the headless module's options) and headless.env (how to
# reach the machine and where the password lives; no secret). An existing
# DIR keeps its flake.nix, machine.nix and flake.lock; settings.json and
# headless.env are written again from the options given.
#
# Extras, all on unless named with --extra-off: neverSleep,
# startAfterPowerLoss, wakeOnLan, powerNapOff, spotlightOff, siriOff.
# shellcheck source=skills/headless/scripts/mac/lib.sh
. "$(dirname "$0")/lib.sh"
EXTRAS=(neverSleep startAfterPowerLoss wakeOnLan powerNapOff spotlightOff siriOff)
TEMPLATE="$SCRIPTS/../assets/darwin"
new_config "$@"
