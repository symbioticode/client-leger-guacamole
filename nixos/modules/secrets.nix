# Secrets — décryptés par sops-nix au boot, jamais en clair dans le repo.
{ config, lib, ... }:

let
  # Le fichier chiffré est créé par :
  #   sops -e --input-type json --output-type json secrets/user-mapping.json > secrets/user-mapping.json.age
  hasUserMapping = builtins.pathExists ../../secrets/user-mapping.json.age;
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
      sopsFile = ../../secrets/user-mapping.json.age;
      owner = "tomcat";
      group = "tomcat";
      mode = "0400";
      path = "/etc/guacamole/user-mapping.xml";
    };
  };
}
