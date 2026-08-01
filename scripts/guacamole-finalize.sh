#!/usr/bin/env bash
# =============================================================================
# guacamole-finalize.sh v1.0
# Tourne sur PROXMOX après nixos-install terminé et la VM éteinte.
# Retire l'ISO installeur, boot scsi0, démarre et attend l'agent QEMU.
#
# Usage : bash guacamole-finalize.sh <VMID>   (défaut : 133)
# =============================================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; NC='\033[0m'
ok()   { echo -e "${GREEN}[OK]${NC}   $*"; }
info() { echo -e "${CYAN}[▸]${NC}    $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
die()  { echo -e "${RED}[FAIL]${NC} $*" >&2; exit 1; }

VMID="${1:-133}"
EXPECTED_IP="${EXPECTED_IP:-192.168.100.210}"

qm status "$VMID" &>/dev/null || die "VM ${VMID} introuvable"

STATUS=$(qm status "$VMID" | awk '{print $2}')
if [[ "$STATUS" != "stopped" ]]; then
  warn "VM ${VMID} n'est pas arrêtée (état: ${STATUS})."
  read -rp "Forcer l'arrêt ? [y/N] " ans
  [[ "$ans" == "y" ]] && qm stop "$VMID" && sleep 3 || die "Arrêt annulé."
fi

info "Retrait des CD-ROM d'installation et de seed..."
qm set "$VMID" --ide2 none 2>/dev/null || true
qm set "$VMID" --ide3 none 2>/dev/null || true
qm set "$VMID" --boot order=scsi0
ok "Boot order réglé sur scsi0"

info "Démarrage..."
qm start "$VMID"

info "Attente de l'agent QEMU (jusqu'à 3 min)..."
FOUND_IP=""
for i in $(seq 1 36); do
  sleep 5
  RESULT=$(qm agent "$VMID" network-get-interfaces 2>/dev/null) || continue
  FOUND_IP=$(echo "$RESULT" | grep -oE '"ip-address" : "[0-9]{1,3}(\.[0-9]{1,3}){3}"' | grep -v '127.0.0.1' | head -1 | grep -oE '[0-9]{1,3}(\.[0-9]{1,3}){3}')
  [[ -n "$FOUND_IP" ]] && break
  echo -n "."
done
echo ""

if [[ -n "$FOUND_IP" ]]; then
  ok "VM ${VMID} en ligne, IP : ${FOUND_IP} (attendu: ${EXPECTED_IP})"
  echo ""
  info "Prochaines étapes :"
  echo "   ssh admin@${FOUND_IP}   # si la clé placeholder a été remplacée"
  echo "   just deploy             # nixos-rebuild switch --flake .#guacamole"
else
  warn "Aucune IP détectée après 3 min. Diagnostic : qm terminal ${VMID}"
fi
