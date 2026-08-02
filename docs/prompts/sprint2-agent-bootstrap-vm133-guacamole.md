# Prompt agent — Bootstrap VM 133 (Guacamole) + documentation

## Contexte
Repo `client-leger-guacamole` (privé), infra de référence décrite dans `docs/architecture.md`
et `docs/DEPLOYMENT.md`. La piste principale (`client-leger-nixos`, VMs Black/Orange) est en
cours de dépannage (lenteur, problème double-NIC) et n'est PAS un prérequis pour ce chantier :
la VM Guacamole n'a qu'une seule carte réseau (vmbr0) et n'est donc pas affectée par ce bug.

Le brief complet (`brief-guacamole-layer.md`, déjà dans le repo/contexte) reste la référence pour
les contraintes de fond (isolation réseau, pas de LDAP/SAML à ce stade, secrets via sops-nix).
Ce prompt-ci porte spécifiquement sur l'exécution du déploiement initial et sa documentation.

## Objectif de la mission
1. Remplacer `PLACEHOLDER_ADMIN_KEY` dans `nixos/hosts/guacamole/default.nix` par la vraie clé
   publique SSH (demander la clé à l'utilisateur si elle n'est pas disponible dans l'environnement
   — ne pas en générer une nouvelle sans consentement explicite).
2. Suivre `docs/DEPLOYMENT.md` étapes 1 à 4 pour créer et installer la VM 133 :
   - `just create-vm-real` (VMID 133, carte unique vmbr0)
   - génération du seed ISO + installation NixOS via `guacamole-live-install.sh`
   - finalisation via `guacamole-finalize.sh 133`
   - accès web `https://192.168.100.210/guacamole/` fonctionnel avec au moins un compte de test
     dans `user-mapping.xml` (peut rester non connecté à Black/Orange à ce stade — l'accès
     RDP réel dépend de la piste principale débloquée).
3. **Ne pas** exécuter `20-guacamole-reachability.yml` ni toucher à vmbr1/vmbr2 — hors scope tant
   que Black/Orange ne sont pas stables.
4. Documenter chaque étape au fur et à mesure, dans le même esprit que `docs/kb001.md` du repo
   `client-leger-nixos` : un journal chronologique factuel (ce qui a été tenté, ce qui a marché,
   ce qui a échoué et pourquoi, la commande exacte qui a résolu un blocage).

## Livrables

### 1. `docs/kb001-guacamole.md` (nouveau fichier, calqué sur le style de kb001.md upstream)
Structure attendue :
- Contexte et objectif (résumé du brief).
- Journal d'exécution par séance/date, avec pour chaque étape : statut (✅/❌/🔄), commande
  exécutée, résultat observé.
- Section "Difficultés rencontrées" : tableau problème / cause / solution, comme dans kb001.md
  upstream — ne pas enjoliver, noter aussi ce qui a échoué et n'a pas (encore) de solution.
- Section "État final vérifié" : sortie de commandes de contrôle réelles (`qm status 133`,
  `curl -k https://192.168.100.210/guacamole/`, etc.), pas une description vague.

### 2. `status.md` (nouveau fichier à la racine, calqué sur `status.md` de `client-leger-nixos`)
Même format tableau : infrastructure, réseau, VM, todolist avec cases à cocher. Doit refléter
l'état réel du repo `client-leger-guacamole` seul (ne pas dupliquer l'état de la piste
principale — juste noter en une ligne que Black/Orange sont "en dépannage, hors scope ici").

## Contraintes
- Toute IP/config découverte en cours de route (ex. IP réellement obtenue si différente de
  192.168.100.210) doit être reflétée fidèlement dans la doc — pas de valeur supposée.
- Aucun secret en clair dans les commits (le test `tests/test-guacamole-config.sh` doit continuer
  à passer).
- Si un blocage survient et n'est pas résolu en fin de session, le documenter comme tel dans
  kb001-guacamole.md (statut ❌ ou 🔄) plutôt que de le passer sous silence — l'objectif est un
  compte-rendu honnête, pas un rapport optimiste.
- Ne pas modifier `client-leger-nixos` ni dépendre de son état pour réussir cette mission.

## Definition of done
- VM 133 up, `qm status 133` = running.
- Page Guacamole accessible en HTTPS depuis le LAN (capture de la commande `curl` de test dans
  la doc, pas juste "ça marche").
- `docs/kb001-guacamole.md` et `status.md` créés et reflètent l'état réel, y compris les échecs.
- `tests/test-guacamole-config.sh` passe toujours.
