# Déploiement — VM Guacamole

Prérequis : accès root SSH à Proxmox (192.168.100.200), `nix` et `just` sur le
poste de contrôle, clé age du parc.

## 0. Préparer le repo

```bash
# 1. Remplacer la clé admin PLACEHOLDER dans
#    nixos/hosts/guacamole/default.nix
#    par la vraie clé publique (ssh-ed25519 ...).

# 2. Créer le secret user-mapping (voir secrets/README.md)
just encrypt-user-mapping
#   -> produit secrets/user-mapping.xml.age (chiffré)
#   -> y renseigner les vrais mdp Windows (sourcés du vault ansible_winrm)
#      et les IPs de connexion RDP (docs/architecture.md §5)

# 3. Vérifier
just check        # nix flake check
just test         # tests locaux
```

## 1. Créer la VM sur Proxmox

```bash
just create-vm-real        # VMID 133, carte unique vmbr0
# ou en dry-run :
just create-vm
```

## 2. Installer NixOS dans l'installeur

Générer le seed ISO (clé de déploiement lecture seule + script d'install), sur le PVE :

```bash
bash scripts/guacamole-make-seed-iso.sh \
  git@github.com:symbioticode/client-leger-guacamole.git \
  ~/.ssh/deploy_guacamole /var/lib/vz/template/iso/guacamole-seed.iso
qm set 133 --ide3 local:iso/guacamole-seed.iso,media=cdrom
```

Puis dans l'installeur NixOS (`qm terminal 133`, quitter : Ctrl+O) :

```bash
sudo mkdir -p /seed
sudo mount /dev/sr1 /seed || sudo mount -L GUACAMOLE_SEED /seed
sudo bash /seed/guacamole-live-install.sh
# À la fin : poweroff
```

> L'installeur auto-login l'utilisateur `nixos` (sudo sans mot de passe).
> Le seed contient la déploy key + l'URL git + la clé age sops ; le script
> clone le repo **dans** l'installeur puis partitionne `/dev/sda`, régénère le
> `hardware-configuration.nix` réel dans le flake, pose la clé age dans la
> cible (`/etc/sops-nix/keys.txt`) et lance
> `nixos-install --flake .#guacamole`.
> Ne pas monter le seed sur `/mnt` (cible installée par le script).
> Alternative sans seed : `sudo bash /seed/guacamole-live-install.sh <chemin-local|url-git>`.

## 3. Finaliser sur Proxmox

```bash
bash scripts/guacamole-finalize.sh 133
#   -> retire le CD, boot scsi0, attend l'agent QEMU, affiche l'IP
```

## 4. Valider

```bash
curl -k https://192.168.100.210/guacamole/     # portail Guacamole (cert auto-signé)
ssh admin@192.168.100.210 'sudo -n nixos-rebuild list-generations'
just deploy                                     # mise à jour du flake
```

## 5. Réseau vers Black/Orange (à valider explicitement)

Choisir l'option A ou B (docs/architecture.md §5), renseigner les `hostname`
des connexions dans `secrets/user-mapping.xml` puis re-chiffrer
(`just encrypt-user-mapping`) et `just deploy`.

## 6. Régression upstream

```bash
just test-upstream
#   -> nix flake check sur client-leger-nixos (lecture seule)
```

## Dépannage rapide

| Symptôme | Piste |
|----------|-------|
| `Support for protocol "rdp" is not installed` | paquet guacamole-server obsolète → vérifier version 1.6.0-unstable+ |
| Login impossible | secret `user-mapping.xml.age` absent/inexact → `just encrypt-user-mapping` |
| Cert self-signed bloquant | ajouter l'exception navigateur ; IP/SAN doit matcher `guacamole.address` |
| RDP coupe au login (freerdp3/GFX) | tester avec `security=rdp` ; documenter dans le comparatif |
| Aucune IP après finalize | `qm terminal 133` ; vérifier DHCP pendant install puis IP statique posée par le flake |
