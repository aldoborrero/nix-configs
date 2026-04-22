{
  description = "Portable home-manager configurations for server environments";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    astronvim = {
      url = "github:aldoborrero/avim.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    llm-agents = {
      url = "github:numtide/llm-agents.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      nixpkgs,
      home-manager,
      astronvim,
      llm-agents,
      ...
    }:
    let
      supportedSystems = [
        "x86_64-linux"
      ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;

      mkHome =
        system:
        {
          username,
          homeDirectory,
          email,
          xdgConfigHome ? null,
          modules ? [ ],
        }:
        home-manager.lib.homeManagerConfiguration {
          pkgs = nixpkgs.legacyPackages.${system};
          extraSpecialArgs = { inherit astronvim llm-agents; };
          modules = [
            ./modules/base.nix
          ]
          ++ modules
          ++ [
            {
              home = {
                inherit username homeDirectory;
                stateVersion = "24.05";
              };
              programs.git.settings.user.email = email;
            }
            (nixpkgs.lib.mkIf (xdgConfigHome != null) {
              xdg.configHome = xdgConfigHome;
            })
          ];
        };
    in
    {
      # home-manager switch --flake .#antics
      homeConfigurations.antics = mkHome "x86_64-linux" {
        username = "argocd";
        homeDirectory = "/root";
        email = "aldo@anthropic.com";
        xdgConfigHome = "/root/src/home/.config";
        modules = [ ./modules/nxb-hosts.nix ];
      };

      apps = forAllSystems (system: {
        default = {
          type = "app";
          program = "${home-manager.packages.${system}.default}/bin/home-manager";
        };
      });
    };
}
