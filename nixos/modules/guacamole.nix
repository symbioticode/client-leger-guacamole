# Module Guacamole — guacd + webapp Tomcat + nginx HTTPS (LAN uniquement).
#
# Choix d'architecture (voir docs/architecture.md) :
#   - services.guacamole-server (guacd) + services.guacamole-client (WAR dans
#     Tomcat) : modules natifs nixpkgs, disponibles et fonctionnels sur
#     nixos-26.05 (freerdp3 fixé, RDP OK). Pas de containers OCI.
#   - Auth locale par user-mapping.xml (fournie par défaut dans le WAR), le
#     fichier étant un secret sops-nix décrypté à l'exécution.
#   - guacd écoute en boucle locale (127.0.0.1:4822) ; le seul point d'entrée
#     réseau est nginx (443/80), lui-même restreint au LAN par le module
#     hardening.nix.
{ config, pkgs, lib, ... }:

let
  cfg = config.guacamole;
  tlsDir = "/var/lib/guacamole-tls";
in
{
  options.guacamole = {
    address = lib.mkOption {
      type = lib.types.str;
      default = "192.168.100.210";
      description = "Adresse IP statique LAN de la VM Guacamole (vmbr0/192.168.100.0/24).";
    };
  };

  config = {
    # ---- Réseau : carte unique sur vmbr0, IP statique, PAS de 2e NIC ----
    networking.usePredictableInterfaceNames = false; # NIC = eth0 (déterministe)
    networking.useDHCP = false;
    networking.interfaces.eth0.ipv4.addresses = [{
      address = cfg.address;
      prefixLength = 24;
    }];
    networking.defaultGateway = "192.168.100.1";
    networking.nameservers = [ "192.168.100.11" "1.1.1.1" ];

    # ---- guacd (guacamole-server) : loopback uniquement ----
    services.guacamole-server = {
      enable = true;
      host = "127.0.0.1";
      port = 4822;
    };

    # ---- Webapp Guacamole dans Tomcat ----
    services.guacamole-client = {
      enable = true;
      enableWebserver = true;
      settings = {
        "guacd-hostname" = "127.0.0.1";
        "guacd-port" = "4822";
      };
    };

    # ---- Certificat TLS auto-signé (LAN) généré au premier boot ----
    # Persiste dans /var/lib ; évite tout secret committé et tout ACME.
    # En production/WireGuard distant : remplacer par un vrai certificat.
    system.activationScripts.guacamole-tls = lib.stringAfter [ "etc" ] ''
      mkdir -p ${tlsDir}
      if [ ! -s ${tlsDir}/server.crt ] || [ ! -s ${tlsDir}/server.key ]; then
        rm -f ${tlsDir}/server.crt ${tlsDir}/server.key
        ${pkgs.openssl}/bin/openssl req -x509 -newkey rsa:2048 -nodes -sha256 \
          -keyout ${tlsDir}/server.key \
          -out ${tlsDir}/server.crt \
          -days 825 \
          -subj "/CN=guacamole.local" \
          -addext "subjectAltName=IP:${cfg.address},DNS:guacamole.local"
      fi
      chmod 600 ${tlsDir}/server.key
      chmod 644 ${tlsDir}/server.crt
    '';

    # ---- nginx HTTPS en frontal (WebSocket pour le tunnel Guacamole) ----
    services.nginx = {
      enable = true;
      recommendedProxySettings = true;
      virtualHosts."guacamole" = {
        listen = [
          { addr = "0.0.0.0"; port = 80; }
          { addr = "0.0.0.0"; port = 443; ssl = true; }
        ];
        addSSL = true;
        sslCertificate = "${tlsDir}/server.crt";
        sslCertificateKey = "${tlsDir}/server.key";
        locations."/" = {
          proxyPass = "http://127.0.0.1:8080/guacamole/";
          proxyWebsockets = true;
          extraConfig = ''
            proxy_buffering off;
            proxy_read_timeout 3600;
            proxy_send_timeout 3600;
          '';
        };
      };
    };
  };
}
