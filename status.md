# status.md — Client Léger Guacamole

> État réel du repo `client-leger-guacamole` (repo indépendant de `client-leger-nixos`,
> même si les deux partagent l'infra Proxmox). Mis à jour le 2026-08-03.

## Infrastructure

| Élément | Valeur | État |
|---|---|---|
| Proxmox VE | `pve.lab.local` — 192.168.100.200 | ✅ up |
| Réseau management | 192.168.100.0/24 (vmbr0) | ✅ |
| Piste principale Black/Orange | repo `client-leger-nixos` (VMs 130/131) | ⚠️ en dépannage, **hors scope ici** |
| Isolation | aucune route vmbr1 ↔ vmbr2 (règle fondatrice) | ✅ respectée |
| Stockage PVE | `/` (pve-root) **100 % plein** ; VG `pve` thin-pool ~40 % (≈140 G libres) | ⚠️ `/` plein (état préexistant) |

## 🚀 Progression 2026-08-03 : install VM 134 par console série (PIVOT)

**Grosse avancée** : le boot headless de l'installeur NixOS est **résolu** — on atteint
l'invite de l'installeur et l'installation est **en cours** sur la **VM 134**.

### Le verrou débloqué (3 pièges)
1. **CD IDE invisible en boot `-kernel`** : `ide2` ne produit aucun `/dev/sr*`
   (stage-1 : `Can't lookup blockdev`, `root=LABEL` timeout). Même avec `ata_piix`
   + `sr_mod` chargés, le contrôleur PIIX IDE n'énumère pas le CD dans ce mode.
2. **Fix = CD-ROM SCSI** : attacher les ISO en `scsi2`/`scsi3` (virtio-scsi déjà
   initialisé par `sda`) → `/dev/sr0`/`sr1` apparaissent, `root=LABEL` fonctionne.
3. **ISO graphique = hang Plymouth** : boote jusqu'au stage-2 puis reste bloqué sur
   *Tell Plymouth To Write Out Runtime Data* (pas de DRM en `vga serial0`, aucun getty
   série). → **passer à l'ISO `minimal`** (pas de splash) + `plymouth.enable=0`.

### Recette (détail complet : `docs/kb002-guacamole-vm134-serial-install.md`)
- ISO **minimal 25.11** (1 654 456 320 o) sur `pve-templates` ; noyau+initrd extraits
  vers `/var/lib/vz/template/iso/guacamole-kernel` + `guacamole-initrd` (chemins lus dans
  `EFI/BOOT/grub.cfg`, entrée `console=ttyS0,115200n8`).
- Boot via `-args -kernel … -append "… root=LABEL=nixos-minimal-25.11-x86_64
  plymouth.enable=0 console=ttyS0,115200n8"` ; ISOs en `scsi2` (installeur) + `scsi3` (seed).
- Console : `socat -u UNIX-CONNECT:/var/run/qemu-server/134.serial0 -`.
- **Résultat** : multi-user + `serial-getty@ttyS0` auto-login `nixos` → invite `nixos@nixos:~$`.

### Réinstallation complète terminée ✅ (pipeline fixé joué de bout en bout)
Le seed a été reconstruit via les **scripts corrigés** (`guacamole-make-seed-iso.sh`
avec **clé age obligatoire**, point 4 MISSION) puis la VM 134 réinstallée depuis
l'installeur avec le **flake GitHub à jour** :
```
partitionnement /dev/sda ✅ → clé age posée /etc/sops-nix/keys.txt ✅
→ hardware-configure généré ♻ → nixos-install --flake .#guacamole ✅
→ systemd-boot + EFI entry → « installation finished! »
```

---

## 🔬 Session actuelle — validation / stabilisation (2026-08-03)

### ✅ Les 2 fixes chocs de MISSION, validés sur la VM réinstallée
- **Console série** (`kernelParams ttyS0` + `boot.loader.timeout`) : boot headless OK,
  login série **root/changeme-firstboot** fonctionne (`initialPassword` validé).
- **Sops au 1er boot** : clé age embarquée dans le seed → `/etc/sops-nix/keys.txt`
  posé à l'install → `user-mapping.xml` **déchiffré** dans `/run/secrets/` ✅.
- **Agent/network** : agent QEMU up, eth0 = **192.168.100.210**, ping OK.
- Backend guacamole **up** : guacd (4822) + webapp Tomcat (8080) 🟢.

### 🔴 Blocage principal en cours : le **switch** casse le système
- **nginx en échec au 1er setup** : `server.key` posté en **600 root** → illisible par
  nginx (BIO_new_file Permission denied). **Corrigé dans la source** (`chgrp nginx`
  + `chmod 640`, commit `09bf274`) — pas encore actif sur la VM.
- **`just deploy` (nixos-rebuild switch --target-host) échoue à l'activation** :
  `Failed to restart boot.mount` / `Failed to start local-fs.target` → le réseau
  tombe, la VM devient muette (ni réseau, ni série). Reproduit **2×** (déjà vu gen2).
- **💡 Cause racine identifiée** : `nixos/hosts/guacamole/hardware-configuration.nix`
  du repo est un **template placeholder** (`device = /dev/disk/by-uuid/REPLACE_ME_ROOT`)
  — les vrais UUIDs générés par `nixos-generate-config` à l'install n'ont **jamais été
  re-poussés**. Tout `nixos-rebuild` depuis le repo réévalue `fileSystems` bidon →
  `boot.mount` change → restart → système en panne.
- **Conséquence** : dépendre de la config repo pour the switch ; il FAUT mettre les
  **vrais UUIDs** dans le repo (fix durable) avant tout redéploiement.

### 🛠 En cours de récupération
- VM 134 de nouveau **injoignable** après le switch échoué (up mais sans réseau,
  serial vide) → reboot inutile (reste down).
- Boot **installeur/redirection** (`-kernel` + `scsi2` minimal + `console=ttyS0`) relancé ;
  `/dev/sda2` monté dans l'installeur pour extraire le **vrai**
  `hardware-configuration.nix` → le déposer dans le repo (fix durable) → redeploy.
- La gen installée reste a priori saine (le switch échoué avait `NIXOS_INSTALL_BOOTLOADER=0`,
  le bootloader n'a pas été réécrit) — à confirmer au prochain boot nominal.

### ⚙️ GitHub / repo : à jour
Commits poussés : `a496f40` (addSSL + console + mdp 1er boot + clé age obligatoire seed) ;
`09bf274` (nginx clé lisible). `flake check` : toujours rouge grondé par la config
**image** (sans `fileSystems`) — préexistant, hors scope P1.

---

## VM Guacamole (VMID 133)

| Champ | Valeur |
|---|---|
| Nom | `guacamole` |
| État | ⏹️ **stopped** — aucune install NixOS fonctionnelle sur disque |
| IP prévue | 192.168.100.210 (jamais observée) |
| Matériel | OVMF (efidisk 4M), scsi0 24G (install interrompue du 02/08 04:00), 2 cores host, RAM 4096, virtio vmbr0 |
| Boot | `scsi0` (ISOs installeur/seed **supprimés** — voir § Tentative image) |
| Réseau | uniquement vmbr0 (aucun pont vers vmbr1/vmbr2) |
| Agent QEMU | activé (`agent: enabled=1`) |
| Accès SSH | clé dédiée `~/.ssh/id_ed25519_guacamole` (comptes admin + root) |

## Tentative du 2026-08-02 soir : image disque via `system.build.images.qemu-efi` (pivot)

### Ce qui a fonctionné ✅
- **Secret sops réparé (point durable)** : `secrets/user-mapping.xml.age` (blob `data` illisible)
  remplacé par `secrets/user-mapping.json.age` — JSON encapsulant la clé `user-mapping.xml`
  (valeur = XML). Clés top-level `['user-mapping.xml', 'sops']`, roundtrip `sops -d` vérifié
  identique au plaintext. Workflow `.json` documenté dans `secrets/README.md`, `justfile`,
  `nixos/modules/secrets.nix`.
- **Build de l'image réussi** : `nix build .#guacamole-qcow2-efi` → `BUILD_RC=0`,
  `result/nixos-image-efi-qcow2-26.05.20260731.5b4f72e-x86_64-linux.qcow2`
  (6,49 Go virtuels / 3,83 Go réels). Le `sops-install-secrets` du manifest s'est passé.
- Flake : `nixosConfigurations.guacamole-image` (sans hardware-config) + package
  `guacamole-qcow2-efi` (variants upstream nixpkgs — `nixos-generators` archivé).

### Ce qui a échoué ❌
- **Import PVE** : `/` plein → copie via LV temporaire `tmp-import` (4G) dans VG `pve` ;
  `qm importdisk` OK (vm-133-disk-2), attaché `scsi1`, redimensionné à 10 G.
- **Clé age injectée** dans `/etc/sops-nix/keys.txt` via `qemu-nbd` (lecture confirmée).
- **Boot de la VM = gel** : lecture disque figée (~41 Mo, 0 écriture), noyau démarré
  (RIP espace modules) mais **root jamais monté** ; console série vide (l'image n'a pas
  `console=ttyS0`), agent QEMU non démarré, aucun ping sur .210.
- **Diagnostic** : le disque était **corrompu** (I/O errors en lecture de `/etc/fstab` et
  `/etc/sops-nix`). Cause probable : la séquence manuelle `sgdisk -e` + `parted resizepart`
  + `resize2fs` sur le thin pool (surprovisionné, attaches nbd) — alors que l'image est
  prévue pour **grandir seule au premier boot** (`x-systemd.growfs` + `boot.growPartition`
  + `autoResize`, fstab par `LABEL=nixos`). Le resize manuel était inutile et nuisible.
- **Arrêt** : budget de **2 h atteint** → abandon de la tentative, comme convenu.

### État PVE après nettoyage
- `vm-133-disk-2` corrompu supprimé ; `scsi1` détaché ; boot restauré `scsi0` ; VM stoppée.
- ISOs `latest-nixos-minimal` et `guacamole-seed` **supprimés** du stockage (le seed contenait
  deploy key + clé age + scripts — à régénérer via `just seed-iso` si reprise de l'install).
- `/` PVE reste 100 % plein (état préexistant, non traité).

### Artefacts restants (machine de contrôle)
- `result/` → image qcow2 6,49 Go (build valide, toujours réutilisable).
- `/tmp/opencode/guac-image-build.log`, `/tmp/opencode/scp-image2.log`.
- Secrets : `secrets/user-mapping.json.age` (à committer) + `user-mapping.json` (gitignoré).

### Prochaines étapes si reprise (lesçons)
1. Réimporter la qcow2 **sans resize manuel** (laisser `boot.growPartition` grandir au 1er boot).
2. Ajouter `boot.kernelParams = [ "console=ttyS0,115200" ]` à la config image → console série visible.
3. Vérifier l'intégrité du disque (e2fsck) **avant** le boot.
4. Puis : finalize (boot scsi, attente agent) → HTTPS `https://192.168.100.210/guacamole/`
   (`guacadmin`/`GuacamoleBootstrap2026!`) → `ssh guacamole` → `docs/kb001-guacamole.md`.

## Todolist mission — VM 134 (voie série, session 2026-08-03)

- [x] Télécharger ISO NixOS 25.11 (minimal + graphique) tailles complètes vérifiées
- [x] Construire/régénérer `guacamole-seed.iso` (deploy key + age key + script) → sr0
- [x] Extraire noyau+initrd 25.11 minimal (chemins depuis `grub.cfg`)
- [x] Boot headless : `-kernel` + CD SCSI + `console=ttyS0` → invite installeur (✔ le verrou)
- [x] `nixos-live-install.sh` → réinstallation complète terminée (systemd-boot + EFI)
- [x] `poweroff` VM 134 → cleanup config (`-kernel` retiré, ISOs retirés, boot scsi0)
- [x] `guacamole-finalize` manuel : agent QEMU up, **IP 192.168.100.210**, ping OK
- [x] Sops au 1er boot validé (`user-mapping.xml` déchiffré) + login série `root`
- [ ] nginx HTTPS opérationnel (`server.key` en 600 root → fix source `09bf274` à déployer)
- [ ] **Déployer les vrais UUIDs `hardware-configuration.nix` dans le repo** (fix du switch)
- [ ] `just deploy` propre (le switch casse `boot.mount` avec le placeholder actuel)
- [ ] HTTPS `https://192.168.100.210/guacamole/` validé (compte de test)
- [ ] `ssh guacamole` OK (clé `id_ed25519_guacamole`)
- [ ] **Dump/export VM stable** (objectif P1) puis commit code final
- [ ] P2 : doc procédure complète + sortir l'image config du `flake check`
- [ ] Ne **pas** exécuter `20-guacamole-reachability.yml` (Black/Orange instables)

### Rappel historique (VM 133 — voie image qcow2, abandonnée)
- [x] Clé admin dédiée / règle sops / scripts `create-vm`*`make-seed`*`live-install`*`finalize`
- [x] Fix bootloader systemd-boot + agent QEMU dans `default.nix` — `01d45ab`
- [x] Secret sops corrigé (`user-mapping.json.age`, roundtrip vérifié)
- [x] Build image qcow2 EFI réussi (mais image corrompue/gel à l'import PVE → abandonnée)

## Notes

- Aucun secret en clair dans le repo (test `just test` = `tests/test-guacamole-config.sh` vert).
- **Le blocage install est levé** (VM 134, voie série) : recette opérationnelle dans
  `docs/kb002-guacamole-vm134-serial-install.md` (boot `-kernel` + CD SCSI + ISO minimal
  25.11 + `console=ttyS0`). Les voies précédentes (install installeur interrompue, image
  qcow2 corrompue) restent documentées dans `docs/kb001-guacamole.md` et les § historiques.
- `docs/kb001-guacamole.md` : chronologie VM 133 (voies image/interrompue) ;
  `docs/kb002-guacamole-vm134-serial-install.md` : procédure opérationnelle retenue.
- Une fois la VM 134 installée : `just deploy` → `nixos-rebuild switch --flake .#guacamole`
  (flake toujours sur 26.05 → le système installé sera **26.05**, l'ISO installeur était 25.11).
