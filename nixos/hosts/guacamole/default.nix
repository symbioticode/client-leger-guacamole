# Configuration hôte — VM Guacamole (proxmox, VMID 133, vmbr0 uniquement).
#
# NB : le hardware-configuration.nix est ajouté PAR LE CONSOMMATEUR
# (flake.nix : config de déploiement « guacamole »), pas ici — sinon l'image
# qemu-efi hériterait des placeholders de fileSystems. Les deux configs
# (deploy + image) partagent ce même fichier.
{ config, pkgs, lib, ... }:
{
  networking.hostName = "guacamole";

  # Bootloader EFI (OVMF) — placé ici car hardware-configuration.nix est
  # régénéré par nixos-generate-config à l'install (sans boot.loader.*).
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.timeout = 3;

  # Console série visible (installation headless : qm terminal / socat).
  boot.kernelParams = [ "console=ttyS0,115200n8" "console=tty1" ];

  # Mot de passe root TEMPORAIRE de premier boot : sert uniquement à ouvrir
  # une session pendant que sops-nix déploie le vrai secret (user-mapping.xml).
  # À retirer dès que la chaîne sops est validée (voir docs/kb002-guacamole-vm134-serial-install.md).
  users.users.root.initialPassword = "changeme-firstboot";

  # Agent QEMU requis par scripts/guacamole-finalize.sh (détection IP).
  services.qemuGuest.enable = true;

  system.stateVersion = "26.05";

  time.timeZone = "America/Montreal";
  i18n.defaultLocale = "fr_CA.UTF-8";
  i18n.supportedLocales = [ "fr_CA.UTF-8/UTF-8" "en_US.UTF-8/UTF-8" ];

  # Utilisateur d'administration (SSH par clé).
  users.users.admin = {
    isNormalUser = true;
    extraGroups = [ "wheel" "tomcat" ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAtNpKi466VEaTrFe3PGYChz1xO9Q8fBPKI90DptDPnp guacamole-vm133"
    ];
  };

  # Clé root : déploiement `nixos-rebuild --target-host root@guacamole`
  # (just deploy) — PermitRootLogin=prohibit-password (hardening.nix).
  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAtNpKi466VEaTrFe3PGYChz1xO9Q8fBPKI90DptDPnp guacamole-vm133"
  ];

  security.sudo.extraRules = [
    {
      users = [ "admin" ];
      commands = [
        { command = "/run/current-system/sw/bin/nixos-rebuild"; options = [ "NOPASSWD" ]; }
        { command = "/nix/store/*/bin/switch-to-configuration"; options = [ "NOPASSWD" ]; }
      ];
    }
  ];

  # Déploiement depuis le poste de contrôle : clef SSH installée pour admin.
  nix.settings = {
    substituters = [ "https://cache.nixos.org" ];
    trusted-public-keys = [ "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=" ];
  };
}
