{
  description = "A headless Mac, set up by the headless skill";

  inputs = {
    headless.url = "github:kunchenguid/headless";
    nixpkgs.follows = "headless/nixpkgs";
    nix-darwin.follows = "headless/nix-darwin";
  };

  outputs = { headless, nix-darwin, ... }: {
    darwinConfigurations.machine = nix-darwin.lib.darwinSystem {
      modules = [ headless.darwinModules.headless ./machine.nix ];
    };
  };
}
