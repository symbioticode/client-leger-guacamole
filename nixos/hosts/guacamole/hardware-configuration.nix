# Hardware — VM NixOS sur Proxmox (virtio, OVMF, QEMU agent).
#
# Ce fichier est un template : le script scripts/guacamole-live-install.sh le
# régénère à l'installation via `nixos-generate-config` (UUIDs réels), puis
# lance `nixos-install --flake .#guacamole`. Les placeholders ci-dessous ne
# servent qu'à ce que le flake évalue en l'absence du fichier généré.
{ config, lib, pkgs, modulesPath, ... }:
{
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
  ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Le disque réel : regeneré par nixos-generate-config à l'install.
  fileSystems."/" = {
    device = "/dev/disk/by-uuid/REPLACE_ME_ROOT";
    fsType = "ext4";
  };
  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/REPLACE_ME_BOOT";
    fsType = "vfat";
  };
  swapDevices = [ ];

  services.qemuGuest.enable = true;
}
