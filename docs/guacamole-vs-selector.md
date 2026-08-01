# Guacamole vs sélecteur fzf+xfreerdp — comparatif objectif

> Statut : **STRUCTURE + PROTOCOLE** — à compléter après **quelques semaines
> d'usage réel** des deux solutions côte à côte. Ce document ne livre **aucune
> recommandation a priori** (exigence du brief) : il définit les critères, la
> méthode de mesure et les cases à remplir avec des observations réelles.

## 1. Contexte

Deux façons d'accéder aux VM Windows 11 (Black/Orange) du parc :

| | **A — Sélecteur (référence)** | **B — Guacamole (parallèle)** |
|---|---|---|
| Client | `fzf` + `xfreerdp` (NixOS, HP ProDesk) | navigateur web (n'importe quel client) |
| Transport | RDP natif, client lourd | RDP → guacd → HTML5/WebSocket |
| Positionnement | solution de référence, robuste, NixOS-centric | couche d'accès web alternative, testée en parallèle |

## 2. Critères et méthode

Chaque critère est mesuré sur le **même couple Black/Orange, mêmes conditions
de réseau LAN** (vmbr0/vmbr1/vmbr2, pas de charge), sessions de travail
réelles. Colonnes remplies après usage.

### 2.1 Latence (RDP natif vs HTML5)

| Métrique | A (xfreerdp) | B (Guacamole) | Méthode |
|----------|--------------|---------------|---------|
| Latence ressentie au clic/clavier | — | — | chronomètre sur action répétitive (défilement, frappe) |
| Fluidité vidéo/scroll | — | — | test de scroll + lecture vidéo courte |
| Coût CPU côté hôte pendant session | — | — | `top` sur VM Windows + hôte |
| Bande passante moyenne | — | — | `vnstat`/`iftop` sur la session |

### 2.2 Expérience utilisateur

| Critère | A | B | Notes |
|---------|---|---|-------|
| Installation client | Aucune (poste NixOS) | Aucune (navigateur) | |
| Démarrage de session | fzf → xfreerdp | onglet navigateur | |
| Multimonitor / résolutions | `-f /multimon` | à valider (HTML5) | |
| Copier-coller bidirectionnel | — | — | |
| Impression locale | — | — | |
| Son | — | — | |
| Session qui survit au changement de client | non | à valider | |
| Notifications/état de connexion | — | — | |

### 2.3 Effort de maintenance

| Critère | A (référence) | B (Guacamole) |
|---------|---------------|---------------|
| Paquets mis à jour | freerdp (NixOS) | guacamole-server + client + Tomcat + nginx |
| Fréquence de maintenance | basse | à mesurer (paquet 1.6.0-unstable) |
| Secrets à gérer | — | user-mapping.xml chiffré sops-nix |
| Composants à surveiller | client seul | guacd + Tomcat + nginx + TLS + sops |
| Dépendance "un seul poste" | oui (NixOS) | non (web) |

### 2.4 Sécurité / réseau

| Critère | A | B |
|---------|---|---|
| Surface réseau | RDP direct 3389 | 443 HTTPS (LAN) + guacd en loopback |
| Isolation Black/Orange | garantie par topologie | garantie (VM sur vmbr0 seul) |
| Accès distant futur | SSH/WireGuard (projet) | WireGuard (aucun port ouvert) |
| Auth | session utilisateur poste | compte Guacamole local (user-mapping) |

### 2.5 Multi-utilisateurs (perspective)

| Critère | A | B |
|---------|---|---|
| Plusieurs utilisateurs simultanés | non prévu | à valider |
| Sessions parallèles sur la même VM Windows | non (1 session RDP) | non (limitation Windows) |
| Gestion des utilisateurs | — | fichier (manuelle) → base si besoin |

## 3. Journal de mesures (à remplir après usage)

| Date | Critère | A | B | Conditions / commentaires |
|------|---------|---|---|---------------------------|
| | | | | |
| | | | | |
| | | | | |

## 4. Bilan provisoire

_À compléter._ Aucune conclusion ici tant que le journal n'est pas rempli sur
plusieurs semaines.

## 5. Prochaines étapes / points à surveiller

- [ ] Vérifier la stabilité RDP Guacamole avec freerdp3 (GFX) sur de longues sessions
- [ ] Tester le multimonitor en HTML5
- [ ] Mesurer le coût CPU du rendu HTML5 côté client léger
- [ ] Décider du chemin réseau Guacamole→Black/Orange (docs/architecture.md §5)
- [ ] Décider ensuite seulement s'il faut poursuivre (multi-utilisateurs) ou
      abandonner la couche web

## 6. Règle de décision (objectivité)

Le brief impose : **pas de recommandation a priori**. La décision de
poursuivre/arrêter Guacamole se prendra uniquement sur :
1. les mesures du journal ci-dessus,
2. un besoin multi-utilisateurs réellement exprimé,
3. la validation du chantier WireGuard (auth LDAP/SAML ensuite, et seulement si besoin).
