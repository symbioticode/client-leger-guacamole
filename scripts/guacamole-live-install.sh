#!/usr/bin/env bash
# =============================================================================
# guacamole-live-install.sh v1.1
# Tourne DANS l'installeur NixOS (VMID 133, une seule session).
#
# Deux sources possibles pour le repo :
#   A) Seed ISO (recommandé) :  sudo mkdir -p /seed
#                               sudo mount /dev/sr1 /seed || sudo mount -L GUACAMOLE_SEED /seed
#                               sudo bash /seed/guacamole-live-install.sh
#      -> le seed contient la déploy key + l'URL git (+ clé age optionnelle)
#         (guacamole-make-seed-iso.sh). NB : ne PAS monter le seed sur /mnt
#         (/mnt = disque cible installé par ce script).
#   B) Passer un repo directement :  sudo bash .../guacamole-live-install.sh <chemin|url>
#      (chemin local ou URL git ; GIT_SSH_COMMAND à positionner si clé SSH)
#
# NB : l'installeur NixOS auto-login l'utilisateur `nixos` (sudo sans mot de
# passe) ; lancer ce script avec `sudo` (root requis : mkfs/mount/nixos-install).
#
# Étapes :
#   1. Récupère le repo (clone via seed/deploy key, ou chemin/URL passé)
#   2. Partitionne/formatte /dev/sda (GPT, ESP 512M, root ext4)
#   3. nixos-generate-config -> régénère hardware-configuration.nix réel
#   4. nixos-install --flake .#guacamole
#   5. poweroff (puis scripts/guacamole-finalize.sh <VMID> sur Proxmox)
# =============================================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; NC='\033[0m'
ok()   { echo -e "${GREEN}[OK]${NC}   $*"; }
info() { echo -e "${CYAN}[▸]${NC}    $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
die()  { echo -e "${RED}[FAIL]${NC} $*" >&2; exit 1; }

REPO_SRC="${1:-}"
DISK="/dev/sda"
REPO_DIR="/root/guacamole-repo"

# ---- 0. Repo source ---------------------------------------------------------
SEED_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "${SEED_DIR}/vars.env" ]]; then
  # Mode A : seed ISO avec déploy key + URL git
  source "${SEED_DIR}/vars.env"
  mkdir -p /root/.ssh
  cp "${SEED_DIR}/deploy_key" /root/.ssh/deploy_key
  chmod 600 /root/.ssh/deploy_key
  cp "${SEED_DIR}/known_hosts" /root/.ssh/known_hosts 2>/dev/null || true
  export GIT_SSH_COMMAND="ssh -i /root/.ssh/deploy_key -o UserKnownHostsFile=/root/.ssh/known_hosts"
  info "Seed détecté — clone de ${GIT_URL} via déploy key"
  rm -rf "$REPO_DIR"
  git clone --depth 1 "$GIT_URL" "$REPO_DIR" || die "Échec du clone (seed)"
elif [[ -n "$REPO_SRC" ]]; then
  if [[ -d "$REPO_SRC" ]]; then
    info "Copie du repo local : $REPO_SRC"
    rm -rf "$REPO_DIR"
    cp -a "$REPO_SRC" "$REPO_DIR"
  else
    info "Clone du repo : $REPO_SRC"
    rm -rf "$REPO_DIR"
    git clone --depth 1 "$REPO_SRC" "$REPO_DIR" || die "Échec du clone"
  fi
  [[ -f "$REPO_DIR/flake.nix" ]] || die "flake.nix introuvable dans le repo"
else
  [[ -d "$REPO_DIR" ]] || die "Aucun repo : seed ISO, <chemin|url>, ou /root/guacamole-repo"
fi

# ---- 1. Partitionnement / formatage -----------------------------------------
info "Partitionnement de ${DISK}..."
umount -R /mnt 2>/dev/null || true
sleep 1
parted -s "$DISK" mklabel gpt
parted -s "$DISK" mkpart ESP fat32 1MiB 512MiB
parted -s "$DISK" set 1 esp on
parted -s "$DISK" mkpart primary ext4 512MiB 100%
sleep 2; partprobe "$DISK" 2>/dev/null || true; sleep 1

mkfs.fat -F 32 "${DISK}1"
mkfs.ext4 -F "${DISK}2"

mount "${DISK}2" /mnt
mkdir -p /mnt/boot
mount "${DISK}1" /mnt/boot
ok "Disque partitionné et monté"

# ---- 1b. Clé age sops-nix dans la cible ---------------------------------------
# Requis pour que sops-install-secrets déchiffre user-mapping.xml dès le
# premier boot de la VM (avant tout scp/nixos-rebuild).
if [[ -f "${SEED_DIR}/age_key" ]]; then
  mkdir -p /mnt/etc/sops-nix
  cp "${SEED_DIR}/age_key" /mnt/etc/sops-nix/keys.txt
  chmod 600 /mnt/etc/sops-nix/keys.txt
  ok "clé age sops-nix posée dans la cible (/etc/sops-nix/keys.txt)"
else
  warn "AUCUNE clé age dans le seed — sops échouera au premier boot."
  warn "Corriger après finalize : scp clé puis re-activer sops."
fi

# ---- 2. Config matérielle réelle ---------------------------------------------
nixos-generate-config --root /mnt
ok "hardware-configuration.nix généré"

# Copie dans le repo pour que le flake voie le vrai matériel
cp /mnt/etc/nixos/hardware-configuration.nix \
   "$REPO_DIR/nixos/hosts/guacamole/hardware-configuration.nix"
info "hardware-configuration.nix copié dans le flake"

# ---- 3. Installation ----------------------------------------------------------
info "nixos-install --flake .#guacamole (peut prendre plusieurs minutes)..."
cd "$REPO_DIR"
nixos-install --flake "$REPO_DIR#guacamole" --no-root-passwd --root /mnt

echo ""
ok "Installation terminée pour guacamole."
info "Éteindre la VM (poweroff), puis depuis Proxmox :"
echo "   bash scripts/guacamole-finalize.sh 133"
