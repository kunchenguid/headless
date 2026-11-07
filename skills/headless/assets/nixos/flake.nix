{
  description = "A headless NixOS machine, set up by the headless skill";

  inputs = {
    headless.url = "github:kunchenguid/headless";
    nixpkgs.follows = "headless/nixpkgs-nixos";
    disko.follows = "headless/disko";
  };

  outputs = { headless, nixpkgs, disko, ... }: {
    nixosConfigurations.machine = nixpkgs.lib.nixosSystem {
      modules = [
        disko.nixosModules.disko
        headless.nixosModules.headless
        ./machine.nix
      ];
    };
  };
}
