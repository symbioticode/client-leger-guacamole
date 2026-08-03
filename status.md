# status.md — Client Léger Guacamole

> État réel du repo `client-leger-guacamole` (repo indépendant de `client-leger-nixos`,
> même si les deux partagent l'infra Proxmox). Mis à jour le 2026-08-02.

## Infrastructure

| Élément | Valeur | État |
|---|---|---|
| Proxmox VE | `pve.lab.local` — 192.168.100.200 | ✅ up |
| Réseau management | 192.168.100.0/24 (vmbr0) | ✅ |
| Piste principale Black/Orange | repo `client-leger-nixos` (VMs 130/131) | ⚠️ en dépannage, **hors scope ici** |
| Isolation | aucune route vmbr1 ↔ vmbr2 (règle fondatrice) | ✅ respectée |
| Stockage PVE | `/` (pve-root) **100 % plein** ; VG `pve` thin-pool ~40 % (≈140 G libres) | ⚠️ `/` plein (état préexistant) |

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

## Todolist mission sprint 2 (`docs/prompts/sprint2-agent-bootstrap-vm133-guacamole.md`)

- [x] Clé admin dédiée générée et configurée (admin **et** root) — commit `e75e85d`
- [x] Règle sops `secrets/.*$` (`sops.yaml`) — `e75e85d`
- [x] Scripts `create-vm-real` / `make-seed-iso` / `live-install` / `finalize` — `e75e85d` + `01d45ab`
- [x] Fix bootloader systemd-boot + agent QEMU dans `default.nix` — `01d45ab`
- [x] VM 133 créée et démarrée ; seed ISO généré et attaché (ide3)
- [x] Secret sops corrigé (`user-mapping.json.age`, roundtrip vérifié) — tentative image
- [x] Build image disque `.#guacamole-qcow2-efi` réussi (qcow2 EFI 6,49 Go)
- [ ] Install NixOS fonctionnelle — **échouée** : install installeur interrompue (04:00) **et** tentative image corrompue/gel (02/08 soir) → **à relancer** (voir § reprise)
- [ ] `guacamole-finalize.sh 133` (boot scsi, attente agent)
- [ ] HTTPS `https://192.168.100.210/guacamole/` validé avec le compte de test
- [ ] `ssh guacamole` OK (clé `id_ed25519_guacamole`)
- [ ] `docs/kb001-guacamole.md` créé
- [ ] `status.md` créé
- [ ] Ne **pas** exécuter `20-guacamole-reachability.yml` (hors scope tant que Black/Orange instables)

## Notes

- Aucun secret en clair dans le repo (test `just test` = `tests/test-guacamole-config.sh` vert).
- L'installation reste le seul blocage. Deux pistes ont échoué : (a) `nixos-install` dans
  l'installeur (lent, interrompu) ; (b) image `qemu-efi` (corruption pendant l'import/resize).
  Le secret sops et le build d'image sont **valides** et réutilisables. La reprise doit
  éviter tout resize manuel et ajouter `console=ttyS0` pour observer le boot.
- `docs/kb001-guacamole.md` est un brouillon (chronologie) à compléter après une install réussie.
