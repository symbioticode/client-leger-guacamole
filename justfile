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
encrypt-user-mapping:
    cp secrets/user-mapping.xml.example secrets/user-mapping.xml
    ${EDITOR:-vi} secrets/user-mapping.xml
    sops -e -i secrets/user-mapping.xml
    mv secrets/user-mapping.xml secrets/user-mapping.xml.age

# --- Tests (ne touche pas à l'infra existante) ---
# Léger : vérifie la config repo localement.
test:
    bash tests/test-guacamole-config.sh

# Alias : valide que le repo client-leger-nixos n'a pas régressé (read-only).
test-upstream:
    bash tests/test-upstream-no-regression.sh
