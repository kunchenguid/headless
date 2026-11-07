{
  description = "A headless NixOS machine, set up by the headless skill";

  inputs = {
    headless.url = "github:kunchenguid/headless";
    nixpkgs.follows = "headless/nixpkgs-nixos";
    disko.follows = "headless/disko";
  };

  outputs = { headless, nixpkgs, disko, ... }:
    let
      machine = nixpkgs.lib.nixosSystem {
        modules = [
          disko.nixosModules.disko
          headless.nixosModules.headless
          ./machine.nix
        ];
      };
      name = machine.config.networking.hostName;
    in
    {
      # `machine` for the skill's apply step; under the host name too, which
      # nixos-rebuild looks for when it builds /etc/nixos on the machine.
      nixosConfigurations = { inherit machine; }
        // nixpkgs.lib.optionalAttrs (name != "" && name != "machine") { ${name} = machine; };
    };
}
