# Durcissement — accès LAN uniquement, SSH par clé, pas de port WAN.
#
# Contrainte du brief : Guacamole joignable UNIQUEMENT depuis le LAN
# (192.168.100.0/24), aucun port exposé sur le WAN, et jamais de tunnel
# vers vmbr1/vmbr2 sans validation explicite. La VM n'a qu'une seule carte
# sur vmbr0 : le « LAN uniquement » est donc structurel (le WAN ne voit
# jamais cette machine). Le pare-feu local reste explicite (défense en
# profondeur) et n'ouvre que 22/80/443.
{ config, pkgs, lib, ... }:
{
  networking.firewall.enable = true;
  networking.firewall.allowedTCPPorts = [ 22 80 443 ];
  networking.firewall.allowPing = true;

  # SSH : clés uniquement, root interdit en mot de passe.
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "prohibit-password";
      KbdInteractiveAuthentication = false;
    };
  };

  # Paquets d'administration/diagnostic.
  environment.systemPackages = with pkgs; [
    curl
    git
    htop
    tcpdump
    # Client RDP pour vérifier depuis la VM (test)
    freerdp
  ];
}
