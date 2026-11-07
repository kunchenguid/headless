{
  description = "A headless NixOS machine, set up by the headless skill";

  inputs = {
    # The NixOS release this machine follows. The machine's own updates
    # (system.autoUpgrade) move this input to the newest revision of it.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    headless.url = "github:kunchenguid/headless";
    headless.inputs.nixpkgs-nixos.follows = "nixpkgs";
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
