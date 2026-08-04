# Procédure minimale — Installation VM NixOS (3 moments)

**Statut :** proposition de simplification — à valider sur un nœud test avant remplacement de KB-003 et du pipeline Guacamole (VM 133) actuels.
**Objectif :** revenir à la structure originale en 3 moments (Proxmox 1 → LiveBoot → Proxmox 2), avec des noms de variables communs aux deux projets (NetPulse, Guacamole) pour que la procédure soit vraiment réutilisable.

Variables à fixer une fois par nœud avant de commencer :

```bash
VMID=133
HOSTNAME=guacamole
REPO_URL=git@github.com:symbioticode/client-leger-guacamole.git
DEPLOY_KEY=~/.ssh/deploy_${HOSTNAME}
SEED_ISO=/var/lib/vz/template/iso/${HOSTNAME}-seed.iso
LIVE_ISO=/var/lib/vz/template/iso/nixos-minimal-25.11-x86_64-linux.iso
```

⚠️ **Toujours l'ISO live 25.11**, jamais "latest" — 26.05 casse l'installeur (voir KB-003, section NixOS 26.05).

---

## MOMENT 1 — Proxmox (préparation + démarrage)

Tout se passe sur l'hôte Proxmox, avant tout accès à la VM.

**1. Télécharger l'ISO live 25.11 (une fois, réutilisable pour tous les nœuds)**
```bash
cd /var/lib/vz/template/iso/
wget -O nixos-minimal-25.11-x86_64-linux.iso \
  https://channels.nixos.org/nixos-25.11/latest-nixos-minimal-x86_64-linux.iso
```

**2. Générer la clé de déploiement (une fois par nœud)**
```bash
ssh-keygen -t ed25519 -f "$DEPLOY_KEY" -N "" -C "deploy-${HOSTNAME}"
```
→ ajouter la clé publique en Deploy Key GitHub (lecture seule) sur le repo cible.

**3. Générer l'ISO seed**
```bash
bash <hostname>-make-seed-iso.sh "$REPO_URL" "$DEPLOY_KEY" "$SEED_ISO"
```
*(script unique à généraliser — actuellement deux variantes existent : `netpulse-make-seed-iso.sh` et `guacamole-make-seed-iso.sh`, quasi identiques)*

**4. Créer la VM avec les deux CD**
```bash
qm create $VMID --name $HOSTNAME --memory 2048 --cores 2 \
  --net0 virtio,bridge=vmbr0 --scsihw virtio-scsi-pci \
  --scsi0 local-lvm:32
qm set $VMID --ide2 local:iso/$(basename "$LIVE_ISO"),media=cdrom
qm set $VMID --ide3 local:iso/$(basename "$SEED_ISO"),media=cdrom
qm set $VMID --boot order='ide2;scsi0'
```

**5. Démarrer et ouvrir le terminal**
```bash
qm start $VMID
qm terminal $VMID
```

→ Fin du Moment 1. Bascule vers le Moment 2 dès que le prompt live NixOS apparaît.

---

## MOMENT 2 — LiveBoot (dans l'installeur, une seule fois)

Tout se passe **dans** la console série de la VM (`qm terminal`), pas sur Proxmox.

**6. Monter le seed** — jamais sur `/mnt` (réservé à la cible d'installation)
```bash
sudo mkdir -p /seed
sudo mount /dev/sr1 /seed || sudo mount -L SEED /seed
```

**7. Lancer le script d'installation unique**
```bash
sudo bash /seed/live-install.sh
```
Ce script doit faire, sans intervention manuelle : clone du repo (deploy key) →
partitionnement de `/dev/sda` → génération de `hardware-configuration.nix` →
écriture de la config (template `sed` ou flake, selon projet) → `nixos-install`
→ **poweroff automatique en fin de script**.

**8. Attendre le poweroff (le script le déclenche lui-même)**
```bash
# rien à taper — le script se termine par `poweroff`
# Ctrl+O pour quitter qm terminal une fois la VM éteinte
```

→ Fin du Moment 2. Ne pas rallumer la VM manuellement ici — c'est le rôle du Moment 3.

---

## MOMENT 3 — Proxmox minimal (finalisation)

Retour sur l'hôte Proxmox.

**9. Retirer les CD, fixer le boot, démarrer, attendre l'IP**
```bash
qm set $VMID --ide2 none
qm set $VMID --ide3 none
qm set $VMID --boot order=scsi0
qm start $VMID
qm agent $VMID network-get-interfaces   # ou script finalize existant
```

**10. Valider l'accès SSH**
```bash
ssh admin@<IP-obtenue>
```

→ Fin. Aucune autre étape manuelle.

---

## Ce qui a fait dérailler l'essai VM 134 (à corriger avant de reformaliser)

- **Confusion VMID** : commandes lancées sur 134 alors que la cible documentée était 133 — vérifier `qm config <VMID>` avant chaque commande si plusieurs VM de test coexistent.
- **Chemin des scripts non fixe** : `scripts/guacamole-finalize.sh` introuvable au premier essai (répertoire courant probablement pas à la racine du clone) — le Moment 3 doit soit cloner le repo sur Proxmox une fois pour toutes dans un chemin fixe (`/root/guacamole-scripts/` ou équivalent), soit ces scripts doivent être copiés hors du flake dans un emplacement stable dès le Moment 1.
- **`shutdown now` sans effet dans `qm terminal`** : le message *"Access denied... interactive authentication"* suggère que la VM était déjà dans un état inhabituel (peut-être pas encore poweroff automatique du script) — le Moment 2 doit se terminer par un poweroff scripté et vérifié, pas par une commande manuelle après coup.
- **Échec au reboot final** : `mounting /dev/root on /iso` puis `iso/nix-store.squashfs` introuvable → le bootloader tente de rebooter sur l'image installeur alors que les CD sont censés être retirés. Vérifier avec `qm config $VMID` juste avant l'étape 9 que `ide2`/`ide3` sont bien passés à `none` et que le `boot order` a pris effet **avant** le `qm start`.

---

## Piste de simplification — automatisation Ansible/script unique

Les 3 moments correspondent à 3 contextes d'exécution différents (Proxmox → Live NixOS via console série → Proxmox), ce qui empêche un vrai "one-shot" simple : on ne peut pas piloter la console série de l'installeur depuis Ansible sans un contrôleur dédié (expect/pexpect, ou API QEMU guest agent une fois le réseau up — indisponible avant install).

Deux niveaux de simplification réalistes, du plus simple au plus ambitieux :

1. **Court terme — un seul script Proxmox orchestrateur** (bash, pas Ansible) qui enchaîne Moment 1 et Moment 3, et n'attend que la fin du Moment 2 (poll sur l'état de la VM : arrêtée = install terminée). Réduit la procédure à 2 commandes humaines : `./deploy-node.sh $HOSTNAME $REPO_URL` (fait tout Moment 1, attend, fait tout Moment 3) — l'opérateur n'a plus qu'à surveiller la console pendant le Moment 2, sans rien taper si le script live est fiable.
2. **Moyen terme — Ansible pour la couche Proxmox uniquement** (Moment 1 + 3 via le module `community.general.proxmox` ou API REST directe), le Moment 2 restant un script bash autonome livré via le seed (déjà le cas). Ansible n'apporte de valeur ici que si tu gères déjà plusieurs nœuds en parc — pour un ou deux nœuds, le script bash unique (option 1) est probablement suffisant et plus simple à déboguer.

Dans les deux cas, la vraie source de complexité actuelle n'est pas l'absence d'orchestration mais la **divergence entre les deux implémentations** (template `sed` vs flake, chemins de scripts non alignés, conventions de nommage différentes) — à unifier dans `mynix` avant d'automatiser, sinon l'orchestrateur devra lui-même gérer deux variantes.
