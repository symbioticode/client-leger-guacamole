# Secrets — décryptés par sops-nix au boot, jamais en clair dans le repo.
{ config, lib, ... }:

let
  # Le fichier chiffré est créé par :
  #   sops secrets/user-mapping.xml   (après édition de secrets/user-mapping.xml.example)
  hasUserMapping = builtins.pathExists ../../secrets/user-mapping.xml.age;
in
{
  sops.age.keyFile = "/etc/sops-nix/keys.txt";

  # Le user-mapping contient les identifiants Windows (Black/Orange) et les
  # comptes Guacamole. Il est injecté là où le webapp Guacamole le cherche
  # (GUACAMOLE_HOME par défaut = /etc/guacamole). Ne PAS utiliser
  # services.guacamole-client.userMappingXml (symlink build-time) : ici le
  # fichier n'existe qu'à l'exécution, après déchiffrement par sops-nix.
  sops.secrets = lib.mkIf hasUserMapping {
    "user-mapping.xml" = {
      sopsFile = ../../secrets/user-mapping.xml.age;
      owner = "tomcat";
      group = "tomcat";
      mode = "0400";
      path = "/etc/guacamole/user-mapping.xml";
    };
  };
}
