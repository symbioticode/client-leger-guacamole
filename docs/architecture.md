# Architecture — Couche d'accès web Guacamole

## Vue d'ensemble

```
[Navigateur]──HTTPS──>[VM Guacamole (VMID 133, NixOS 26.05)]
                          │
                          ├─ nginx :443/80 (LAN uniquement, cert self-signed)
                          │    └── proxy /guacamole/ (WebSocket)
                          │         └── Tomcat :8080 (guacamole-client WAR)
                          │              └── /etc/guacamole/user-mapping.xml   ← secret sops-nix
                          │              └── guacd 127.0.0.1:4822
                          │
                          └── eth0 UNIQUE sur vmbr0 (192.168.100.210)
```

La VM n'a **qu'une seule carte** sur `vmbr0`. Elle n'est jamais dual-homed vers
`vmbr1`/`vmbr2` : conformément au brief, elle ne devient pas un second pont
entre Black et Orange (NextCloud reste le seul pont autorisé).

## Décisions

### 1. Modules natifs NixOS plutôt que containers OCI

`services.guacamole-server` (guacd) + `services.guacamole-client` (WAR dans
Tomcat) sont disponibles et **fonctionnels sur nixos-26.05** :

- le paquet `guacamole-server` (1.6.0-unstable-2025-06-29) intègre le correctif
  freerdp3 qui a restauré le support du protocole RDP dans nixpkgs
  (issue nixpkgs #395919, fixé par PR #407726) ;
- un test NixOS upstream (`nixosTests.guacamole-server`) couvre guacd ;
- c'est cohérent avec le reste du parc : tout est NixOS, pas de couche Docker
  supplémentaire, reproductible via le flake.

**Conteneur OCI (déprécié ici)** : utilisé si/quand le paquet NixOS devient
trop rigide ou en retard sur les versions (ex. besoin d'une extension non
packagée). C'est la bascule documentée, pas le choix par défaut : les images
officielles Apache sont une sécurité, mais ajoutent une runtime conteneur +
une gestion d'état, contre-productive pour une VM unique du parc.

### 2. Authentification locale (user-mapping.xml), pas de LDAP/SAML/OIDC

Conformément au brief, **pas de fournisseur d'identité à ce stade** :
- le user-mapping.xml est le mécanisme d'auth par défaut **embarqué dans le
  WAR Guacamole** (aucune extension à installer) ;
- il est stateless (pas de base de données à administrer) — parfait pour
  valider le chantier avec un petit nombre d'utilisateurs ;
- le passage à une base intégrée (guacamole-auth-jdbc) reste possible plus
  tard si un vrai besoin multi-utilisateurs avec gestion web des connexions
  se confirme. C'est un choix documenté, réversible.

Le fichier `user-mapping.xml` contient les **mots de passe Windows**
(`administrator` de Black/Orange) : il est chiffré dans le repo via
**sops-nix** et décrypté à l'exécution vers `/etc/guacamole/user-mapping.xml`
(module `secrets.nix`). Rien en clair dans git, même privé.

### 3. Réseau : LAN uniquement, pas de port WAN

- Carte unique sur `vmbr0` → la machine n'est **jamais** exposée au WAN
  (structurelle, pas seulement pare-feu) ;
- pare-feu local explicite : 22/80/443 uniquement ;
- `guacd` écoute en **loopback** (127.0.0.1:4822), jamais exposé ;
- TLS auto-signé généré au premier boot (LAN de confiance ; à remplacer par un
  vrai certificat le jour où l'accès distant WireGuard arrive).

### 4. Accès distant futur (WireGuard)

Guacamole écoute **en interne** (pas de port ouvert). Quand la couche
WireGuard de homebridge sera en place, elle donnera accès au LAN depuis
l'extérieur — aucune modification de Guacamole requise, rien à exposer.

### 5. Joignabilité de Black/Orange en RDP (à valider explicitement)

La VM étant sur `vmbr0` uniquement, il faut décider du chemin vers les IPs
Windows. **Deux options**, à trancher avec la validation réseau du projet
(le brief exige une validation explicite avant tout accès vers vmbr1/vmbr2) :

| Option | Mécanisme | Change l'hôte ? | Isolation |
|--------|-----------|-----------------|-----------|
| **A. NIC de gestion sur vmbr0** (recommandée) | Black/Orange ont une NIC de gestion avec IP statique sur 192.168.100.0/24 ; user-mapping pointe vers ces IPs | Non | Impeccable : aucune route vers vmbr1/vmbr2, les IPs de gestion sont sur le LAN |
| **B. Redirection contrôlée par l'hôte** | Playbook gated `20-guacamole-reachability.yml` : DNAT sur l'hôte (13389→Black, 13390→Orange), source = IP Guacamole uniquement | Oui (ip_forward + iptables) | À valider : règles très restrictives, aucune route vmbr1↔vmbr2 |

Par défaut, le user-mapping pointe vers `10.0.1.100` / `10.0.2.100` (IPs de
l'inventaire), modifiables dans le secret sops. Le playbook B est **gated**
(ne fait rien sans `-e apply_guacamole_reachability=true`) et documenté comme
exigeant une validation explicite avant exécution.

## Secrets

| Secret | Usage | Emplacement |
|--------|-------|-------------|
| `secrets/user-mapping.xml.age` | comptes Guacamole + connexions RDP + mdp Windows | décrypté → `/etc/guacamole/user-mapping.xml` |

Clé age : identique au parc (`sops.yaml`, même identité que
client-leger-nixos). Clé privée sur la machine de contrôle et sur la VM
(`/etc/sops-nix/keys.txt`).

## Ce qui est volontairement HORS scope

- LDAP/SAML/OIDC (attend la validation du chantier WireGuard + besoin réel) ;
- migration DB (guacamole-auth-jdbc) ;
- exposition WAN (jamais) ;
- modification de `client-leger-nixos` (aucune).
