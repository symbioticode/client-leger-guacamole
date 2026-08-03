default: test

# --- Vérifications ---
check:
    nix flake check

# --- Déploiement ---
# Usage : just deploy          (hôte par défaut 192.168.100.210)
deploy host='192.168.100.210':
    nixos-rebuild switch --flake .#guacamole --target-host root@{{host}}

# --- Proxmox : création de la VM ---
create-vm:
    bash scripts/proxmox-create-guacamole-vm.sh --dry-run

create-vm-real:
    bash scripts/proxmox-create-guacamole-vm.sh

# Génère le seed ISO (déploy key + script d'install) et l'attache à la VM.
# Usage : just seed-iso
#   GIT_URL=git@github.com:symbioticode/client-leger-guacamole.git
#   DEPLOY_KEY=~/.ssh/deploy_guacamole
#   OUTPUT_ISO=/var/lib/vz/template/iso/guacamole-seed.iso
seed-iso GIT_URL='git@github.com:symbioticode/client-leger-guacamole.git' DEPLOY_KEY='~/.ssh/deploy_guacamole' OUTPUT_ISO='/var/lib/vz/template/iso/guacamole-seed.iso':
    bash scripts/guacamole-make-seed-iso.sh {{GIT_URL}} {{DEPLOY_KEY}} {{OUTPUT_ISO}}

# --- Secrets ---
# Édite secrets/user-mapping.json (plaintext, gitignoré) puis chiffre vers
# secrets/user-mapping.json.age (commitable). Le .age sert de secret sops
# nommé "user-mapping.xml" (format JSON imposé : l'extension .xml génère un
# blob `data` que sops-install-secrets ne sait pas lire).
encrypt-user-mapping:
    cp -f secrets/user-mapping.json.example secrets/user-mapping.json
    ${EDITOR:-vi} secrets/user-mapping.json
    sops -e --input-type json --output-type json secrets/user-mapping.json > secrets/user-mapping.json.age

# --- Tests (ne touche pas à l'infra existante) ---
# Léger : vérifie la config repo localement.
test:
    bash tests/test-guacamole-config.sh

# Alias : valide que le repo client-leger-nixos n'a pas régressé (read-only).
test-upstream:
    bash tests/test-upstream-no-regression.sh
