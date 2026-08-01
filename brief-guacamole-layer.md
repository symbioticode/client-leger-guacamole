# Brief agent — Couche d'accès web Guacamole (repo séparé)

## Contexte
Le repo `client-leger-nixos` (privé, github.com/symbioticode) contient l'infra de référence :
Proxmox VE (pve.lab.local, réseau 192.168.100.0/24) + client léger NixOS 26.05 (HP ProDesk 600 G3)
+ deux VM Windows 11 isolées (Black sur vmbr1/10.0.1.0/24, Orange sur vmbr2/10.0.2.0/24) + NextCloud
prévu en pont de fichiers (VM 102, 10.0.1.0 + 10.0.2.0 + management).

Ce nouveau chantier est **indépendant** : il ne remplace rien de l'existant (sélecteur `fzf` +
`xfreerdp` reste la solution "client léger" de référence, robuste, NixOS-centric). Guacamole est
une **couche d'accès web alternative**, testée en parallèle, sur la même infra Proxmox/NixOS.
Objectif : explorer un accès "n'importe quel client, juste un navigateur" pour un usage
multi-utilisateurs futur, sans toucher à l'infra existante ni à ses garanties d'isolation réseau.

## Repo
Nouveau repo séparé, ex. `github.com/symbioticode/client-leger-guacamole` (privé pour l'instant).
Ne PAS committer dans `client-leger-nixos`.

## Objectifs (par ordre de priorité)

1. **VM Guacamole sur Proxmox**, gérée en NixOS (cohérence avec le reste du parc) :
   - module `services.guacamole-server` (guacd) + `services.tomcat` pour la WAR guacamole-client,
     ou containers OCI (`virtualisation.oci-containers`) si le paquet NixOS s'avère trop rigide —
     documenter le choix et pourquoi.
   - Cette VM se connecte à vmbr0 (management) uniquement au départ. Ne PAS la rendre dual-homed
     vers vmbr1/vmbr2 sans validation explicite — ce serait un second pont entre Black et Orange,
     hors du périmètre de sécurité déjà établi (NextCloud est le seul pont autorisé).
2. **Connexions Guacamole** vers Black et Orange en RDP, en réutilisant les creds `administrator`
   déjà présents dans `ansible_winrm` (à sourcer depuis un vault, pas en clair).
3. **Authentification locale d'abord** (fichier `user-mapping.xml` ou base intégrée), PAS de LDAP/
   SAML/OIDC à ce stade — cette étape ne vient qu'après validation du chantier 3 (WireGuard) et
   uniquement si un vrai besoin multi-utilisateurs se confirme.
4. **Accès réseau** : pas de port entrant exposé sur le WAN. Guacamole doit être joignable
   uniquement depuis le LAN 192.168.100.0/24, et plus tard via un tunnel WireGuard si l'accès
   distant est requis (voir note ci-dessous). Ne pas ouvrir de port sur la box internet.
5. **Documentation** : produire un `docs/guacamole-vs-selector.md` qui compare objectivement les
   deux approches (latence RDP native vs HTML5, expérience utilisateur, effort de maintenance)
   après quelques semaines d'usage réel — pas une recommandation a priori.

## Contraintes non-négociables
- Ne modifie AUCUN fichier du repo `client-leger-nixos` existant.
- N'ouvre aucune route entre vmbr1 et vmbr2 (règle fondatrice du projet : isolation Black/Orange).
- Pas de dépendance à un fournisseur d'identité commercial (Microsoft/Okta/etc.) pour l'instant.
  Si un jour SAML Microsoft est requis (contrainte externe), il devra rester optionnel et
  coexister avec un mode d'authentification 100% auto-hébergé fonctionnel sans lui.
- Toute credential Windows utilisée par Guacamole doit être stockée via un mécanisme de secret
  NixOS (`sops-nix` ou `agenix`), jamais en clair dans le repo, même privé.

## Note sur le futur WireGuard (hors scope immédiat)
L'utilisateur a déjà commencé à poser des briques dans homebridge
(github.com/dravitch/homebridge), qui prévoit une couche WireGuard en remplacement du tunnel SSH.
Cette couche WireGuard, une fois en place, devient le mécanisme d'accès distant pour Guacamole
(remplace le besoin d'exposer un port). Ne pas l'implémenter dans ce chantier — juste garder
l'architecture compatible (Guacamole écoute en interne, jamais exposé directement).

## Livrables attendus
- Config NixOS de la VM Guacamole (flake + modules), déployable comme les autres VM du parc.
- Playbook ou script Ansible/Nix reproductible pour créer la VM sur Proxmox.
- `docs/guacamole-vs-selector.md` (comparatif après usage).
- Aucune régression sur l'infra existante — validation finale : `just test` sur
  `client-leger-nixos` doit toujours passer sans modification.
