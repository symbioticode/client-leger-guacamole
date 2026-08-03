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
      # Modules communs VM Guacamole (hors hardware-configuration.nix).
      guacamoleModules = [
        sops-nix.nixosModules.sops
        ./nixos/modules/secrets.nix
        ./nixos/modules/guacamole.nix
        ./nixos/modules/hardening.nix
        ./nixos/hosts/guacamole/default.nix
      ];
    in
    {
      # Déploiement sur la VM installée : inclut le hardware-configuration
      # (régénéré à l'installation par nixos-generate-config).
      nixosConfigurations.guacamole = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = guacamoleModules ++ [
          ./nixos/hosts/guacamole/hardware-configuration.nix
        ];
      };

      # Build d'image disque bootable (qcow2 EFI) sans hardware-configuration :
      # les fileSystems/partitions sont posés par le variant d'image.
      nixosConfigurations.guacamole-image = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = guacamoleModules;
      };

      # Image disque : nix build .#guacamole-qcow2-efi
      #   -> importdisk sur Proxmox, boot OVMF direct.
      packages.${system}.guacamole-qcow2-efi =
        self.nixosConfigurations.guacamole-image.config.system.build.images.qemu-efi;

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
