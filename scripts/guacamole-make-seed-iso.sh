#!/usr/bin/env bash
# =============================================================================
# guacamole-make-seed-iso.sh v1.0
# Tourne sur PROXMOX (hôte). Génère un petit ISO "seed" contenant :
#   - une clé de déploiement SSH (lecture seule, dédiée à ce chantier)
#   - le script d'installation (guacamole-live-install.sh)
#   - l'URL git du repo client-leger-guacamole
#   - known_hosts github.com (pas de prompt interactif)
#
# Le repo est cloné DANS l'installeur (via la déploy key) : aucun plaintext
# (ni secrets, ni clés) ne transite/circule en dehors de ce seed temporaire.
#
# Prérequis :
#   - genisoimage sur l'hôte Proxmox (apt install -y genisoimage)
#   - une clé de déploiement LECTURE SEULE sur le repo GitHub privé
#     (Settings > Deploy keys > Add) — voir KB-003 du parc mynix.
#
# Usage :
#   ./guacamole-make-seed-iso.sh <git_url> <deploy_key_path> <output_iso>
# Exemple :
#   ./guacamole-make-seed-iso.sh \
#     git@github.com:symbioticode/client-leger-guacamole.git \
#     ~/.ssh/deploy_guacamole \
#     /var/lib/vz/template/iso/guacamole-seed.iso \
#     ~/.config/sops/age/keys.txt        # [optionnel] clé age du parc
#
# Le 4e argument (optionnel) embarque la clé age dans le seed : le script
# d'installation la copie dans la cible (/mnt/etc/sops-nix/keys.txt) pour que
# sops-install-secrets déchiffre user-mapping.xml dès le premier boot.
# L'ISO seed est temporaire (détachée par guacamole-finalize.sh) et vit sur le
# stockage local du PVE (LAN homelab).
# =============================================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
ok()   { echo -e "${GREEN}[OK]${NC}   $*"; }
info() { echo -e "${CYAN}[▸]${NC}    $*"; }
die()  { echo -e "${RED}[FAIL]${NC} $*" >&2; exit 1; }

[[ $# -lt 3 || $# -gt 4 ]] && die "Usage: $0 <git_url> <deploy_key_path> <output_iso> [age_key_path]"

GIT_URL="$1"
DEPLOY_KEY="$2"
OUTPUT_ISO="$3"
AGE_KEY="${4:-}"

command -v genisoimage &>/dev/null || die "genisoimage manquant : apt install -y genisoimage"
[[ ! -f "$DEPLOY_KEY" ]] && die "Clé de déploiement introuvable : $DEPLOY_KEY"

WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ -f "${SCRIPT_DIR}/guacamole-live-install.sh" ]] || \
  die "guacamole-live-install.sh introuvable à côté de ce script."

cp "${SCRIPT_DIR}/guacamole-live-install.sh" "${WORKDIR}/guacamole-live-install.sh"
cp "$DEPLOY_KEY" "${WORKDIR}/deploy_key"
cp "${DEPLOY_KEY}.pub" "${WORKDIR}/deploy_key.pub" 2>/dev/null || true
chmod 600 "${WORKDIR}/deploy_key"

if [[ -n "$AGE_KEY" ]]; then
  [[ ! -f "$AGE_KEY" ]] && die "Clé age introuvable : $AGE_KEY"
  cp "$AGE_KEY" "${WORKDIR}/age_key"
  chmod 600 "${WORKDIR}/age_key"
  ok "clé age embarquée (${AGE_KEY})"
else
  info "pas de clé age dans le seed (sops ne déchiffrera pas au premier boot)"
fi

ssh-keyscan -t ed25519 github.com > "${WORKDIR}/known_hosts" 2>/dev/null
ok "known_hosts github.com généré"

cat > "${WORKDIR}/vars.env" <<EOF
GIT_URL="${GIT_URL}"
EOF

mkdir -p "$(dirname "$OUTPUT_ISO")"
genisoimage -o "$OUTPUT_ISO" -V "GUACAMOLE_SEED" -J -r "$WORKDIR" >/dev/null
ok "ISO seed créé : ${OUTPUT_ISO}"

echo ""
info "Prochaine étape — attacher ce CD à la VM :"
echo "   qm set 133 --ide3 local:iso/$(basename "$OUTPUT_ISO"),media=cdrom"
echo ""
info "Puis, dans l'installeur NixOS (qm terminal 133) :"
echo "   sudo mkdir -p /seed"
echo "   sudo mount /dev/sr1 /seed || sudo mount -L GUACAMOLE_SEED /seed"
echo "   sudo bash /seed/guacamole-live-install.sh"
