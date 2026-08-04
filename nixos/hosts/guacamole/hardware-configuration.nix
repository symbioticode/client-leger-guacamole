# Hardware — VM Guacamole sur Proxmox (virtio, OVMF, QEMU agent).
#
# UUIDs réels du disque installé (extraits de la VM 134 avec
# `nixos-generate-config` à l'installation). Garder ces UUIDs pour que
# `nixos-rebuild switch` (just deploy) n'altère PAS boot.mount/local-fs.target
# — le placeholder REPLACE_ME_* faisait redémarrer boot.mount et plantait le
# système (voir status.md, session 2026-08-03).
{ config, lib, pkgs, modulesPath, ... }:
{
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
  ];

  boot.initrd.availableKernelModules = [ "ata_piix" "uhci_hcd" "virtio_pci" "virtio_scsi" "sd_mod" "sr_mod" ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-intel" ];
  boot.extraModulePackages = [ ];

  fileSystems."/" = {
    device = "/dev/disk/by-uuid/08177c6c-c13b-485e-976d-3b7583b77cb7";
    fsType = "ext4";
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/CFCE-DC11";
    fsType = "vfat";
    options = [ "fmask=0022" "dmask=0022" ];
  };

  swapDevices = [ ];

  services.qemuGuest.enable = true;
}