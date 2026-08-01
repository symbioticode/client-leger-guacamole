#!/usr/bin/env bash
# =============================================================================
# proxmox-create-guacamole-vm.sh v1.0
# Création de la VM Guacamole sur Proxmox (OVMF/EFI + console série + agent).
#
# VMID 133 — Guacamole, carte UNIQUE sur vmbr0 (192.168.100.0/24), PAS de
# seconde carte vers vmbr1/vmbr2 (contrainte du brief : pas de pont
# Black/Orange). IP statique posée par le flake NixOS après installation
# (nixos/hosts/guacamole/default.nix + module guacamole.nix).
#
# Usage :
#   bash proxmox-create-guacamole-vm.sh [--dry-run] [--vmid 133]
#
# Variables surchargeables :
#   VMID HOSTNAME MEMORY CORES DISK_SIZE ISO_NAME STORAGE BRIDGE
# =============================================================================

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

ok()   { echo -e "${GREEN}[OK]${NC}    $*"; }
fail() { echo -e "${RED}[FAIL]${NC}  $*" >&2; }
info() { echo -e "${CYAN}[▸]${NC}     $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC}  $*"; }
sep()  { echo -e "${BOLD}────────────────────────────────────────────────────${NC}"; }
die()  { fail "$*"; exit 1; }

DRY_RUN=0
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=1 && warn "MODE DRY-RUN"

run() {
  if [[ $DRY_RUN -eq 1 ]]; then
    echo -e "  ${YELLOW}[DRY]${NC} $*"
  else
    eval "$@"
  fi
}

[[ $EUID -ne 0 ]] && die "Root requis (hôte Proxmox)"

# ── Configuration (surchargeable) ────────────────────────────────────────────
VMID="${VMID:-133}"
HOSTNAME="${HOSTNAME:-guacamole}"
MEMORY="${MEMORY:-4096}"
CORES="${CORES:-2}"
ISO_STORAGE="${ISO_STORAGE:-local}"
ISO_NAME="${ISO_NAME:-latest-nixos-minimal-x86_64-linux.iso}"
STORAGE="${STORAGE:-local-lvm}"
DISK_SIZE="${DISK_SIZE:-24}"
BRIDGE="${BRIDGE:-vmbr0}"
STATIC_IP="${STATIC_IP:-192.168.100.210}"

sep
echo -e "${BOLD}Création VM ${VMID} (${HOSTNAME}) — Guacamole / NixOS / ${BRIDGE}${NC}"
sep

# ── Vérifications ─────────────────────────────────────────────────────────────
info "Vérifications..."
ISO_PATH="/var/lib/vz/template/iso/${ISO_NAME}"
[[ ! -f "$ISO_PATH" ]] && die "ISO introuvable : $ISO_PATH"
ok "ISO : $ISO_NAME"

if qm status "$VMID" &>/dev/null; then
  warn "VMID $VMID existe déjà — destruction et recréation"
  run "qm stop $VMID --skiplock 1 2>/dev/null || true"
  sleep 2
  run "qm destroy $VMID --destroy-unreferenced-disks 1 --purge 1"
fi

if ! pvesm status | grep -q "^${STORAGE}"; then
  fail "Storage '${STORAGE}' introuvable."
  die "Corriger STORAGE="
fi
ok "Storage : ${STORAGE}"
ok "Bridge  : ${BRIDGE} (SEUL NIC — pas de dual-homing vmbr1/vmbr2)"

# ── Création VM ───────────────────────────────────────────────────────────────
sep; info "Création de la VM..."
run "qm create $VMID \
  --name '$HOSTNAME' \
  --memory $MEMORY \
  --cores $CORES \
  --cpu host \
  --numa 1 \
  --balloon 0 \
  --tablet 0 \
  --onboot 1 \
  --ostype l26 \
  --scsihw virtio-scsi-pci \
  --net0 virtio,bridge=${BRIDGE},firewall=0"
ok "VM créée (VMID: $VMID, RAM: ${MEMORY}MB, CPU: ${CORES})"

run "qm set $VMID --scsi0 ${STORAGE}:${DISK_SIZE},cache=writeback,discard=on"
ok "Disque système : ${DISK_SIZE} GB"

run "qm set $VMID --efidisk0 ${STORAGE}:1,format=raw,efitype=4m,pre-enrolled-keys=0"
ok "EFI disk"

run "qm set $VMID --bios ovmf"
ok "BIOS : OVMF"

run "qm set $VMID --cdrom ${ISO_STORAGE}:iso/${ISO_NAME}"
ok "CD-ROM : $ISO_NAME"

run "qm set $VMID --boot order='ide2;scsi0'"
ok "Boot order : CD → scsi0"

run "qm set $VMID --serial0 socket --vga serial0"
ok "Console : serial0 (qm terminal)"

run "qm set $VMID --agent enabled=1,fstrim_cloned_disks=1"
ok "QEMU agent activé"

run "qm set $VMID --description 'VM Guacamole — ${HOSTNAME}
OS: NixOS 26.05
Role: Couche d acces web (guacd + Tomcat + nginx HTTPS)
Reseau: ${BRIDGE} uniquement, IP statique ${STATIC_IP} (LAN 192.168.100.0/24)
Isolation: pas de NIC vmbr1/vmbr2 (seul pont autorise: NextCloud VM 102)
Created: $(date +%Y-%m-%d)'"
ok "Description"

sep; info "Démarrage..."
run "qm start $VMID"
ok "VM démarrée"

[[ $DRY_RUN -eq 0 ]] && sleep 3

# ── Résumé ────────────────────────────────────────────────────────────────────
sep
echo -e "${BOLD}${GREEN}VM $HOSTNAME (VMID $VMID) créée et démarrée.${NC}"
echo ""
echo -e "  RAM: ${MEMORY}MB | CPU: ${CORES} cores | Disque: ${DISK_SIZE}GB | BIOS: OVMF"
echo -e "  Réseau: ${BRIDGE} (unique) — IP finale prévue: ${STATIC_IP}"
echo ""
echo -e "${BOLD}1. Console :${NC} qm terminal $VMID   (quitter: Ctrl+O)"
echo ""
echo -e "${BOLD}2. Seed ISO (sur l'hôte PVE) — clé déploy + script d'install :${NC}"
echo -e "   ${CYAN}bash scripts/guacamole-make-seed-iso.sh \\${NC}"
echo -e "   ${CYAN}  git@github.com:symbioticode/client-leger-guacamole.git \\${NC}"
echo -e "   ${CYAN}  ~/.ssh/deploy_guacamole /var/lib/vz/template/iso/guacamole-seed.iso${NC}"
echo -e "   ${CYAN}qm set $VMID --ide3 local:iso/guacamole-seed.iso,media=cdrom${NC}"
echo ""
echo -e "${BOLD}3. Dans l'installeur NixOS — lancer l'installation :${NC}"
echo -e "   ${CYAN}mount /dev/sr1 /mnt || mount -L GUACAMOLE_SEED /mnt${NC}"
echo -e "   ${CYAN}bash /mnt/guacamole-live-install.sh${NC}"
echo ""
echo -e "${BOLD}4. Après nixos-install — depuis le PVE :${NC}"
echo -e "   ${YELLOW}bash scripts/guacamole-finalize.sh $VMID${NC}"
echo ""
