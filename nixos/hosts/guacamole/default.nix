# Configuration hôte — VM Guacamole (proxmox, VMID 133, vmbr0 uniquement).
{ config, pkgs, lib, ... }:
{
  imports = [
    ./hardware-configuration.nix
  ];

  networking.hostName = "guacamole";

  system.stateVersion = "26.05";

  time.timeZone = "America/Montreal";
  i18n.defaultLocale = "fr_CA.UTF-8";
  i18n.supportedLocales = [ "fr_CA.UTF-8/UTF-8" "en_US.UTF-8/UTF-8" ];

  # Utilisateur d'administration (SSH par clé).
  # ⚠️ Remplacer la clé PLACEHOLDER par la vraie clé publique AVANT tout
  # déploiement (voir docs/DEPLOYMENT.md).
  users.users.admin = {
    isNormalUser = true;
    extraGroups = [ "wheel" "tomcat" ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA PLACEHOLDER_ADMIN_KEY"
    ];
  };

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
