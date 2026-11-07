# This Mac's config. The headless skill writes settings.json (the headless
# module's options, see its README); add anything else you want on this Mac
# below, then run the skill's apply step again.
{ ... }:
{
  headless = builtins.fromJSON (builtins.readFile ./settings.json);

  nixpkgs.hostPlatform = "aarch64-darwin";
  system.stateVersion = 6;
}
