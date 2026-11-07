# This Mac's config. The headless skill writes settings.json (the headless
# module's options, listed in the skill's references/mac.md and defined in
# modules/darwin/headless.nix of github:kunchenguid/headless); add anything
# else you want on this Mac below, then run the skill's apply step again.
{ ... }:
{
  headless = builtins.fromJSON (builtins.readFile ./settings.json);

  nixpkgs.hostPlatform = "aarch64-darwin";
  system.stateVersion = 6;
}
