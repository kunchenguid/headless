# This machine's config. The headless skill writes settings.json (the
# headless module's options, listed in the skill's references/linux.md and
# defined in modules/nixos/headless.nix of github:kunchenguid/headless) and
# system.nix (the machine's disks, boot loader and hardware); add anything
# else you want on this machine below, then run the skill's apply step again.
{ ... }:
{
  imports = [ ./system.nix ];

  headless = builtins.fromJSON (builtins.readFile ./settings.json);
}
