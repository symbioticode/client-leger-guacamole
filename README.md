# client-leger-guacamole

Couche d'accès web **Guacamole** pour l'infrastructure Client Léger
(Proxmox + NixOS + VM Windows 11 Black/Orange).

> Chantier **indépendant** de `client-leger-nixos` : il n'y remplace rien, ne
> modifie aucun de ses fichiers et ne touche pas à l'isolation Black/Orange.
> Guacamole est une alternative web **testée en parallèle** du sélecteur
> `fzf`+`xfreerdp` de référence.

## Composants

- **VMID 133** sur Proxmox, NixOS 26.05, **carte unique sur vmbr0**
  (jamais dual-homed → jamais un second pont Black/Orange).
- **guacd** (`services.guacamole-server`) en loopback + **webapp Guacamole**
  (`services.guacamole-client`) dans Tomcat, fronté par **nginx HTTPS**
  (cert auto-signé LAN).
- **Auth locale** `user-mapping.xml` (embarqué dans le WAR, aucun fournisseur
  d'identité commercial). Les mots de passe Windows y sont injectés depuis un
  secret **sops-nix** chiffré — jamais en clair.
- **Accès LAN uniquement** ; aucun port WAN ; futur accès distant via WireGuard
  (hors scope, architecture déjà compatible).

## Structure

```
flake.nix                      # flake NixOS (nixpkgs 26.05 + sops-nix)
nixos/modules/guacamole.nix    # guacd + client + nginx HTTPS + réseau vmbr0
nixos/modules/secrets.nix      # sops-nix (user-mapping.xml décrypté)
nixos/modules/hardening.nix    # pare-feu LAN-only, SSH par clé
nixos/hosts/guacamole/         # config hôte + hardware-configuration.nix
secrets/                       # user-mapping.xml.age (chiffré) + example
scripts/                       # proxmox-create-guacamole-vm.sh, live-install, finalize
ansible/                       # inventory + playbook gated de joignabilité RDP
docs/                          # architecture, deployment, guacamole-vs-selector
tests/                         # tests locaux + non-régression upstream
```

## Démarrage rapide

```bash
just check                 # nix flake check
just test                  # tests locaux
just encrypt-user-mapping  # créer secrets/user-mapping.xml.age
just create-vm-real        # créer la VM sur Proxmox (VMID 133)
just deploy                # nixos-rebuild switch --flake .#guacamole
```

Voir **[docs/DEPLOYMENT.md](docs/DEPLOYMENT.md)** pour la procédure complète et
**[docs/architecture.md](docs/architecture.md)** pour les choix de conception
(modules natifs vs containers, auth locale, joignabilité RDP à valider).
