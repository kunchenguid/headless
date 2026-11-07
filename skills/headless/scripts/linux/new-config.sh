#!/bin/bash
# new-config.sh - make a Linux machine's config folder on this computer, or
# update the settings of one.
#
# usage: new-config.sh DIR --address ADDRESS --login LOGIN --password-ref REF
#          [--ssh-key PATH] [--host-name NAME] [--no-auto-login]
#          [--tailscale] [--tailscale-key-ref REF] [--tailscale-login-server URL]
#          [--extra-off NAME]... [--keep-password-ssh]
#
# DIR becomes a git folder holding settings.json (the headless settings,
# the same for NixOS and for the distro-neutral script) and headless.env
# (how to reach the machine and where the password lives; no secret). The
# NixOS files (flake.nix, machine.nix, system.nix) arrive later, from
# apply.sh on a NixOS machine or install-nixos.sh; an existing DIR keeps
# them. settings.json and headless.env are written again from the options
# given.
#
# Extras, both on unless named with --extra-off: neverSleep, autoUpdates.
# shellcheck source=skills/headless/scripts/linux/lib.sh
. "$(dirname "$0")/lib.sh"
EXTRAS=(neverSleep autoUpdates)
TEMPLATE=""
new_config "$@"
