{
  description = "Client Léger Guacamole — Couche d'accès web (VM NixOS sur Proxmox)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    sops-nix.url = "github:Mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, sops-nix }:
    let
      system = "x86_64-linux";
    in
    {
      nixosConfigurations.guacamole = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          sops-nix.nixosModules.sops
          ./nixos/modules/secrets.nix
          ./nixos/modules/guacamole.nix
          ./nixos/modules/hardening.nix
          ./nixos/hosts/guacamole/default.nix
        ];
      };

      # Modules réutilisables (déploiement, tests, autres nœuds)
      nixosModules = {
        guacamole = ./nixos/modules/guacamole.nix;
        secrets = ./nixos/modules/secrets.nix;
        hardening = ./nixos/modules/hardening.nix;
      };

      devShells.${system}.default = nixpkgs.legacyPackages.${system}.mkShell {
        packages = with nixpkgs.legacyPackages.${system}; [
          sops
          age
          just
          freerdp
          curl
          git
        ];
      };
    };
}
