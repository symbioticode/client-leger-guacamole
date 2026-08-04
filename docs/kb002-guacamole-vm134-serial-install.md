# kb002-guacamole-vm134-serial-install.md — Install headless VM 134 par console série

> Procédure opérationnelle qui a permis de passer du **boot d'une ISO NixOS 25.11
> dans une VM Proxmox headless (`vga serial0`, aucun écran)** jusqu'à **l'exécution de
> l'installeur final** (`guacamole-live-install.sh`). Rédigé après réussite — détaille
> aussi les voies qui ont échoué pour ne pas les refaire.
>
> VM visée : **134** (`guacamole`, IP prévue `192.168.100.210`), hôte `pve.lab.local`.

## Objectif

Installer NixOS sur la VM 134 **sans écran**, uniquement via la console série
(`serial0` en socket QEMU) : tout le peu que l'on voit du boot passe par le port série.

Le verrou central : **voir une invite** dans l'installeur NixOS puis lancer
l'installation (`nixos-install`), en observant la sortie.

---

## Le fond du problème : 3 pièges rencontrés

### 1. Le CD-ROM IDE n'apparaît PAS en boot `-kernel` direct
Quand on démarre la VM sans firmware GRUB via `-args -kernel/-initrd` (pour
contourner le menu gfxterm invisible), **le lecteur IDE (`ide2`) ne produit aucun
périphérique `/dev/sr*`**. `/dev/root` reste introuvable → `root=LABEL=…` échoue →
stage-1 tombe dans un shell d'urgence (utilisable, mais pas de média bootable).

Vérifié dans le shell d'urgence : `ata_piix` et `sr_mod` chargés, mais aucun `sr0`
dans `/proc/partitions`. Le contrôleur PIIX IDE n'énumère pas le CD dans ce mode.

### 2. La solution : monter les ISO en **CD-ROM SCSI (virtio-scsi)**
La VM possède un contrôleur `virtio-scsi-pci` **déjà initialisé** (le disque de boot
`sda` y est attaché). Les périphériques CD attachés via `scsi2`/`scsi3` apparaissent
alors comme `/dev/sr0` `/dev/sr1` → `root=LABEL=…` et `mount -L GUACAMOLE_SEED`
fonctionnent.

- préalable : remplacer `ide2`/`ide3` par `scsi2`/`scsi3` (media=cdrom).

### 3. L'ISO **graphique** se bloque sur Plymouth (pas de sortie série)
- L'ISO graphique boote jusqu'au stage-2 systemd puis **reste suspendu sur
`A start job is running for Tell Plymouth… Write Out Runtime Data`** : l'écran
de splash requiert un framebuffer/DRM qui n'existe pas en `vga serial0`, et aucun
getty série n'est lancé → VM inutilisable.
- **L'ISO *minimal*** n'a pas de couche splash → **boote proprement** jusqu'au
multi-user, avec un `serial-getty@ttyS0` en **auto-login `nixos`**.

> Conclusion : pour un install headless série, **préférer l'ISO "*minimal*"**.

---

## Procédure pas-à-pas (reproductible)

> Commandes exécutées sur `pve.lab.local` (SSH clé `id_ed25519_proxmox`) sauf indication.

### 0. Télécharger et vérifier les ISO (taille OBLIGATOIRE complète)
```
# sur PVE, stockage pve-templates (= /mnt/pve-templates/template/iso) :
stat -c %s /mnt/pve-templates/template/iso/latest-nixos-minimal-x86_64-linux.iso
  # minimal 25.11 = 1654456320 octets → vérifier via isoinfo -d (Volume size × 2048)
```
> Piège : ne JAMAIS attacher d'ISO **tronquée** (un renommage prématuré d'un `.tmp_dwnl`
> avait créé une image de 2,8 Go au lieu de 3,74 Go → `TASK ERROR`). Attendre la fin
> du téléchargement et contrôler la taille exacte.

### 1. Extraire noyau + initrd + chemin `init=` depuis l'ISO minimal
Monter l'ISO et lire son `grub.cfg` (l'entrée taguée `console=ttyS0,115200n8`) :
```
mkdir -p /mnt/min; mount -o loop,ro <iso> /mnt/min
grep -A1 "console=ttyS0,115200n8" /mnt/min/EFI/BOOT/grub.cfg
```
Retenir les 3 chemins (unique par build) :
- **kernel** : `/boot//nix/store/8a1f…-linux-6.12.93/bzImage`
- **initrd** : `/boot//nix/store/7qim…-initrd-linux-6.12.93/initrd`
- **init** : `/nix/store/nhz…-nixos-system-nixos-25.11.12484.b6018f87da91/init`
- **label racine** : `root=LABEL=nixos-minimal-25.11-x86_64`

Copier noyau+initrd sur le stockage local :
```
cp /mnt/min/boot/nix/store/8a1f…/bzImage /var/lib/vz/template/iso/guacamole-kernel
cp /mnt/min/boot/nix/store/7qim…/initrd   /var/lib/vz/template/iso/guacamole-initrd
chmod 644 /var/lib/vz/template/iso/guacamole-kernel /var/lib/vz/template/iso/guacamole-initrd
```

### 2. Configurer la VM en boot `-kernel` + CD-ROM SCSI
```
qm set 134 --args "-kernel /var/lib/vz/template/iso/guacamole-kernel \
   -initrd /var/lib/vz/template/iso/guacamole-initrd \
   -append \"init=/nix/store/<INIT>/init boot.shell_on_fail \
   root=LABEL=nixos-minimal-25.11-x86_64 nohibernate loglevel=4 \
   lsm=landlock,yama,bpf plymouth.enable=0 console=ttyS0,115200n8\""

# CD-ROM en SCSI (pas IDE)
qm set 134 --scsi2 pve-templates:iso/latest-nixos-minimal-x86_64-linux.iso,media=cdrom
qm set 134 --scsi3 local:iso/guacamole-seed.iso,media=cdrom
```
- Arguments-clés de la cmdline : `console=ttyS0,115200n8` (sortie + getty),
  `plymouth.enable=0` (pas de splash), `boot.shell_on_fail`.

### 3. Booter et lire la console
```
qm start 134
socat -u UNIX-CONNECT:/var/run/qemu-server/134.serial0 -
```
Sortie attendue (fin de boot) :
```
<<< Welcome to NixOS 25.11… (x86_64) - ttyS0 >>>
[nixos user|nixos (automatic login)]
nixos@nixos:~$
```

### 4. Monter le seed et lancer l'installation (sur la console série)
```
lsblk -o +LABEL        # sr0=GUACAMOLE_SEED, sr1=nixos-minimal-25.11-x86_64
sudo mkdir -p /seed
sudo mount -L GUACAMOLE_SEED /seed || sudo mount /dev/sr1 /seed
ls /seed               # deploy_key, age_key, guacamole-live-install.sh, …
```
Lancer **détaché** (survit à la déconnexion de la console) avec log :
```
sudo setsid bash /seed/guacamole-live-install.sh > /tmp/live-install.log 2>&1 < /dev/null &
tail /tmp/live-install.log
```

### 5. Après `nixos-install` terminé + poweroff
```
# sur Proxmox :
bash scripts/guacamole-finalize.sh 134
# → retire les CD SCSI, boot scsi0, démarre, attend l'agent QEMU (IP attendue 192.168.100.210)
```

---

## Tableau de diagnostic (cause → solution)

| Symptôme (console) | Cause | Solution |
|---|---|---|
| Stage-1 : `Timed out waiting for device /dev/root… Can't lookup blockdev` | CD **IDE** non énuméré en boot `-kernel` | passer le CD installeur en **SCSI** (`scsi2`) |
| `emergency` shell, aucune `sr*` | même (ata_piix/sr chargés mais aucun sr) | `qm set … --scsi2 …` au lieu de `ide2` |
| Stage-2 : `A start job is running for Tell Plymouth…` (jamais fini, muet) | ISO **graphique** + splash sur `vga serial0` | utiliser l'ISO **minimal** + `plymouth.enable=0` |
| Console muette ou menu gfxterm invisible | GRUB en mode gfx/image | contourner GRUB via `-args -kernel` + `console=ttyS0` |
| Install « muette » / perdue en zone console | `nixos-install` attaché à la session | lancer avec `setsid … > log 2>&1 < /dev/null &` |
| Aucun `/mnt` monté, erreur `must be superuser` | seed monté sur `/mnt` (chemin réservé) | monter sur `/seed` + `sudo` |

---

## Chemins de référence sur PVE (état fin de séance)
- `/var/lib/vz/template/iso/guacamole-kernel` + `guacamole-initrd` (25.11 minimal)
- `/var/lib/vz/template/iso/guacamole-seed.iso` (deploy key + age key + script)
- `/mnt/pve-templates/template/iso/latest-nixos-minimal-x86_64-linux.iso` (1,65 Go)
- `/mnt/pve-templates/template/iso/latest-nixos-graphical-x86_64-linux.iso` (3,74 Go, inutilisée headless)
- Console : `socat -u UNIX-CONNECT:/var/run/qemu-server/134.serial0 -`

## Reprises / astuces
- Le `init=` change entre builds (graphical `mgws…` vs minimal `nhzq…`) : toujours lire
  le `grub.cfg` de **l'**ISO utilisée, ne pas reprendre un chemin d'une autre.
- seed/installer peuvent s'inverser (sr0/sr1) : privilégier le *label* `GUACAMOLE_SEED`.
- Ne pas interrompre `nixos-install` (long) ; suivre le log au lieu de la console.