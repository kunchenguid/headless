{
  description = "Headless machine setup: a nix-darwin module, a starting config, and the headless agent skill";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nix-darwin.url = "github:nix-darwin/nix-darwin/master";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, nix-darwin }: {
    # The headless layer for a Mac: import it and set `headless.*`.
    darwinModules.headless = ./modules/darwin/headless.nix;
    darwinModules.default = self.darwinModules.headless;

    # The starting config the skill copies into a folder on your computer.
    templates.darwin = {
      path = ./skills/headless/assets/darwin;
      description = "A headless Mac's nix-darwin config, using the headless module";
    };
    templates.default = self.templates.darwin;

    # The template's own machine settings, built as an example system, so
    # `nix flake check` proves the module and the template evaluate and build.
    darwinConfigurations.example = nix-darwin.lib.darwinSystem {
      modules = [
        self.darwinModules.headless
        ./skills/headless/assets/darwin/machine.nix
        # The template's key is a placeholder the module refuses; the skill
        # puts the user's own key there.
        { headless.sshKeys = nixpkgs.lib.mkForce [ "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMypJnmwSE7hhkQADVWGRLHsEeA6BU2Sj/TxykcHxHcP flake-check" ]; }
      ];
    };
    checks.aarch64-darwin.example = self.darwinConfigurations.example.system;
  };
}
