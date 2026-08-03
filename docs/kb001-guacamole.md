# kb001-guacamole.md — Journal d'installation VM 133 (Guacamole)

> Journal chronologique factuel du bootstrap de la VM NixOS Guacamole sur Proxmox
> (`pve.lab.local`, VMID 133, réseau management 192.168.100.0/24 uniquement).
> Objectif : `https://192.168.100.210/guacamole/` fonctionnel avec un compte de test.
> Rédigé au fil de l'exécution, y compris ce qui a échoué.

## Contexte et objectif

Couche d'accès web Guacamole (remplaçante potentielle / complément du sélecteur fzf+xfreerdp),
déployée en parallèle sur la même infra Proxmox, **sans toucher** à `client-leger-nixos`
(Black/Orange en dépannage, hors scope). VM mono-NIC sur vmbr0 uniquement ; pas de route
vmbr1↔vmbr2 ; secrets via sops-nix ; aucune dépendance à un fournisseur d'identité.

## Journal d'exécution

### Séance 1 — 2026-08-02 (matin, avant 02:00)

| Statut | Étape | Commande | Résultat observé |
|---|---|---|---|
| ✅ | Exploration env | `qm list` ; `ls /var/lib/vz/template/iso/` | PVE SSH OK (clé `id_ed25519_proxmox`) ; ISO NixOS absent → à télécharger |
| ✅ | Téléchargement ISO | `wget` de `latest-nixos-minimal-x86_64-linux.iso` | `nixos-minimal-26.05.6603.5b4f72e1705a-x86_64-linux.iso`, **1 694 498 816 octets** exacts |
| ✅ | Clé admin dédiée | `ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_guacamole` | pub `...AAAtNpKi466VEaTrFe3PGYChz1xO9Q8fBPKI90DptDPnp guacamole-vm133` |
| ✅ | Clé posée dans le flake | `nixos/hosts/guacamole/default.nix` | admin **et** root ; `just check` + `just test` OK |
| ✅ | Compte de test chiffré | `sops --config sops.yaml -e secrets/user-mapping.xml` | `secrets/user-mapping.xml.age` (`guacadmin`) ; `rm` du clair |
| ✅ | Règle sops élargie | `secrets/.*$` | sinon `sops` → « no matching creation rules found » |
| ✅ | VM créée et démarrée | `bash scripts/proxmox-create-guacamole-vm.sh` | OVMF, scsi0 24G, RAM 4096, 2 cores, vmbr0 seul, serial0 socket, `vga serial0`, agent, ide2=NixOS ISO, boot `ide2;scsi0`, onboot 1 |
| ✅ | Correction hostname | `qm set 133 --name guacamole` | défaut `VM_HOSTNAME` corrigé dans le script (builtin PVE `HOSTNAME` était erroné) |
| ✅ | Seed ISO construit | `bash scripts/guacamole-make-seed-iso.sh ... age_key` | `guacamole-seed.iso` (378 Ko) : deploy key (clé GitHub `symbioticode` faute de `deploy_guacamole`), `vars.env` (GIT_URL), **clé age**, `known_hosts` github |
| ✅ | Seed attaché | `qm set 133 --ide3 local:iso/guacamole-seed.iso,media=cdrom` | sr1 monté par `mount /dev/sr1 /seed` |
| ✅ | GRUB série navigué | pilote `pilote_serial.py` | menu GRUB → Options → *Serial console* → noyau + shell sur ttyS0 ; confirmé `PING_SERIAL_OK_1785649440` |
| ❌ | 1re tentative d'install | `sudo bash /seed/guacamole-live-install.sh` (seed monté sur `/mnt`) | `mount: /mnt: must be superuser to use mount` → **corrigé** : seed sur `/seed` + `sudo` (scripts + `DEPLOYMENT.md`) |

### Séance 2 — 2026-08-02, ~01:21 (relance install #1)

| Statut | Étape | Commande | Résultat observé |
|---|---|---|---|
| ✅ | Relance install | `sudo mkdir -p /seed && sudo mount /dev/sr1 /seed || sudo mount -L GUACAMOLE_SEED /seed; sudo bash /seed/guacamole-live-install.sh` | clone GitHub OK (45 objects), partition + mkfs OK, clé age posée (`/mnt/etc/sops-nix/keys.txt`), `hardware-configuration.nix` généré + copié dans le flake, `nixos-install` lancé |
| ❌ | Échec `nixos-install` (~35 min) | — | **`error: Failed assertions: You must set the option boot.loader.grub.devices ...`** — `/mnt/nix/var/nix/profiles/` vide, `/mnt/boot` vide |
| ✅ | Diagnostic | `lsblk -f ; ls /mnt/nix/var/nix/profiles/ ; ls /mnt/boot/` | disque partitionné (sda1 vfat /mnt/boot, sda2 ext4 /mnt) mais aucun profil système ni bootloader |
| ✅ | **Cause racine trouvée** | lecture `guacamole-live-install.sh` + `default.nix` | le bootloader était dans le **template** `hardware-configuration.nix`, mais l'installeur le **régénère** via `nixos-generate-config` (sans `boot.loader.*`) → assertion GRUB |

### Fix — 2026-08-02 (~02:05)

| Statut | Étape | Commande | Résultat observé |
|---|---|---|---|
| ✅ | Bootloader + agent dans `default.nix` | `nixos/hosts/guacamole/default.nix` | `boot.loader.systemd-boot.enable = true` ; `boot.loader.efi.canTouchEfiVariables = true` ; `services.qemuGuest.enable = true` |
| ✅ | Évaluation validée | `nix eval .#nixosConfigurations.guacamole.config.system.build.toplevel.drvPath` | `.drv` produit, **plus d'assertion** |
| ✅ | Commit + push | `git commit -m "install: bootloader systemd-boot + agent QEMU dans default.nix ..."` | `01d45ab` → origin |

### Séance 3 — 2026-08-02, ~02:07 (relance install #2, flake corrigé)

| Statut | Étape | Commande | Résultat observé |
|---|---|---|---|
| ✅ | Relance détachée | `sudo setsid bash /seed/guacamole-live-install.sh > /tmp/install-full2.log 2>&1 < /dev/null &` | survit à la déconnexion console ; journal lisible après coup |
| ✅ | Progression | `tail /tmp/install-full2.log` + IO `/proc/<qemu>/io` | clone OK, partition OK, clé age OK, `nixos-install` lancé ; **évaluation passe** (plus d'assertion), téléchargement du closure : `write_bytes` 4,25→6,5 Go, **encore active à 03:05** |
| ❌ | **Interruption à 04:00** (selon utilisateur) | — | l'installation était **encore incomplète** à ce moment (téléchargement du closure non terminé) ; cause exacte non établie (pas de télémétrie entre 03:05 et 19:31) |

### Séance 4 — 2026-08-02, ~19:31 (constat post-interruption)

| Statut | Étape | Commande | Résultat observé |
|---|---|---|---|
| 🔄 | VM relancée sur installeur | `qm status 133` ; `ps ... -p <qemu>` | running ; **PVE up depuis 6 min** (19:25), VM 133 relancée (PID 2002, 19:30:46, onboot=1) ; ide2 (ISO NixOS) + ide3 (seed) toujours attachés ; boot `ide2;scsi0;ide3` |
| 🔄 | Console série | captures `qm terminal 133 -iface serial0` + socat | **muette** : pas de GRUB, aucun écho aux commandes (`lsblk`, `echo READY_PING`) ; à diagnostiquer / relancer l'install |

## Difficultés rencontrées

| Problème | Cause | Solution (ou statut) |
|---|---|---|
| Console série monopolisée (sortie volée) | socat/vncterm multiples sur la même socket série (1 seul client actif) | fermer les consoles web/`qm terminal` concurrentes ; piloter depuis une seule session |
| `mount: /mnt: must be superuser to use mount` | seed monté sur `/mnt` + shell non-root | **corrigé** : seed sur `/seed` + `sudo` (scripts + docs) |
| Assertion `boot.loader.grub.devices` | bootloader uniquement dans le template `hardware-configuration.nix`, écrasé par `nixos-generate-config` à l'install | **corrigé** (`01d45ab`) : `systemd-boot` + `canTouchEfiVariables` + `qemuGuest` dans `default.nix` |
| Sortie install perdue | `nixos-install` attaché à une session console qui se ferme (EOF → logout → login recyclé) | **corrigé** : lancer l'install détachée (`setsid ... > /tmp/install-full2.log 2>&1 < /dev/null &`) puis lire le journal |
| Install tuée en plein téléchargement | **interruption à 04:00** (install encore incomplète à ce moment ; cause exacte non établie — PVE relancé à ~19:25, VM 133 redémarrée 19:30:46) | 🔄 à relancer (flake déjà corrigé, seed + ISO toujours en place) |
| Console série muette après reboot PVE | non déterminé (le boot précédent affichait GRUB sur série) | 🔄 à diagnostiquer (check GRUB/video, `-nographic` + `vga serial0`) |

## État final vérifié (2026-08-02, ~19:35)

Sorties réelles (pas de valeur supposée) :

```
$ qm status 133
status: running

$ qm config 133 | grep -E "^boot|vga|serial|ostype|agent"
agent: enabled=1,fstrim_cloned_disks=1
boot: order=ide2;scsi0;ide3
ostype: l26
serial0: socket
vga: serial0

$ qm list
  VMID NAME        STATUS    MEM(MB)  BOOTDISK(GB)
   130 client-leger-black   stopped
   131 client-leger-orange  running
   133 guacamole            running        24.00

# Flake : évaluation OK (assertion levée)
$ nix eval --raw .#nixosConfigurations.guacamole.config.system.build.toplevel.drvPath
/nix/store/4ymrip7j5f0ws286p8l18wknr0z67f45-nixos-system-guacamole-26.05.20260731.5b4f72e.drv
```

Non encore vérifié (bloqué par l'installation) :
- `curl -k https://192.168.100.210/guacamole/` → **en attente** (système final pas installé).
- `ssh guacamole` (clé `id_ed25519_guacamole`) → **en attente**.
- `just deploy` / `nixos-rebuild switch --flake .#guacamole` → **en attente**.

## Prochaines étapes

1. Diagnostiquer la console muette (GRUB/vidéo après reboot PVE) ou relancer l'install détachée
   (`guacamole-live-install.sh` depuis `/seed`).
2. Après `nixos-install` terminé : `bash scripts/guacamole-finalize.sh 133` (détache ide2+ide3,
   boot `scsi0`, attente agent QEMU, IP attendue 192.168.100.210).
3. Valider HTTPS + SSH + `just deploy`.
4. Nettoyer sur PVE : `/tmp/seed-build/` (clé GitHub `id_ed25519_symbioticode`, `age_key_tmp`) après install.
