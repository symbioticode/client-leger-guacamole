# Mission agent — Corriger et retester le pipeline d'installation VM 133/134 (guacamole)

**Contexte :** deux tentatives d'installation de bout en bout (VM 134, testée le 2026-08-03)
ont échoué à cause de défauts de configuration non documentés dans le flake et les scripts
`guacamole-*`. La procédure a fonctionné jusqu'à `nixos-install`, mais le système installé
était inutilisable (pas de console série, pas d'agent QEMU, secrets sops non déchiffrés,
mot de passe admin jamais posé). Cette mission consiste à corriger la **source** (repo
`client-leger-guacamole`), pas à rejouer un rattrapage manuel.

**Ne pas modifier :** la structure du repo, l'architecture Black/Orange, `client-leger-nixos`
(lecture seule, régression via `just test-upstream`).

---

## Défauts identifiés à corriger dans le flake (`nixos/hosts/guacamole/` ou `nixos/modules/`)

1. **Console série absente sur le système installé**
   Le système *installeur* nécessite une sélection manuelle au menu de boot
   (`Options > Serial console=ttyS0,115200n8`), mais le système *installé* (le flake)
   n'a jamais forcé cette sortie non plus — résultat : après `finalize`, la console
   série (`qm terminal`) ne répond plus, obligeant à repasser en VGA pour diagnostiquer.
   → Ajouter dans la config du host :
   ```nix
   boot.kernelParams = [ "console=ttyS0,115200n8" "console=tty1" ];
   boot.loader.timeout = 3;
   ```

2. **Agent QEMU non activé**
   `guacamole-finalize.sh` échoue systématiquement à détecter l'IP après 3 min
   (`[WARN] Aucune IP détectée`) parce que `services.qemuGuest.enable` n'est pas
   dans la config. Ce n'est pas un délai réseau, c'est une absence structurelle.
   → Ajouter :
   ```nix
   services.qemuGuest.enable = true;
   ```

3. **Aucun compte utilisable au premier boot**
   `admin` dépend d'un secret (mot de passe hashé via sops) qui n'a jamais pu être
   déchiffré (voir point 4), et `root` est verrouillé par défaut — donc **zéro accès**
   possible au système fraîchement installé tant que sops n'a pas fonctionné une
   première fois. C'est un point de blocage total, pas un inconvénient mineur.
   → Ajouter un mot de passe root temporaire **non secret**, valable uniquement le
   temps du premier boot, à retirer/changer après validation du pipeline sops :
   ```nix
   users.users.root.initialPassword = "changeme-firstboot";
   ```
   (ou `users.users.admin.initialPassword` selon lequel des deux comptes est la
   porte d'entrée standard — à trancher et documenter, pas les deux en parallèle)

4. **Clé age sops absente du seed par défaut**
   `guacamole-make-seed-iso.sh` accepte un 4ᵉ argument optionnel (chemin vers la
   clé age) mais ne l'exige pas et n'a pas de valeur par défaut — résultat :
   `sops-install-secrets` échoue silencieusement pendant `nixos-install`
   (`Activation script snippet 'setupSecrets' failed (1)`), sans bloquer l'install
   mais en laissant le système sans mots de passe RDP fonctionnels.
   → Corriger `guacamole-make-seed-iso.sh` pour que l'argument clé age soit
   **obligatoire**, ou ait un défaut explicite (`~/guacamole-age-key` si présent),
   avec échec dur (`exit 1`) si absent — pas un simple `[WARN]` qui laisse
   continuer un pipeline qui produira un système cassé.

## Défauts identifiés à corriger dans les scripts

5. **Nom de fichier incohérent entre doc et script réel**
   La doc/README référence `live-install.sh` à un endroit ; le script réel s'appelle
   `guacamole-live-install.sh`. Confirmé source d'erreur en session (deux échecs
   `No such file or directory` avant de trouver le bon nom).
   → Harmoniser tous les noms de scripts entre `docs/DEPLOYMENT.md`, les
   commentaires inline des scripts, et les noms de fichiers réels. Un seul nom
   par script, partout.

6. **Chemin des scripts non fixe sur Proxmox**
   `scripts/guacamole-finalize.sh` introuvable au premier essai (répertoire
   courant non aligné avec la racine du clone) — retrouvé ensuite sous
   `~/guacamole-scripts/` (chemin ad hoc, pas celui du repo).
   → Décider et documenter un chemin fixe unique sur l'hôte Proxmox pour les
   scripts opérationnels (ex. `/root/guacamole-scripts/` cloné une fois depuis
   le repo, jamais improvisé), et le référencer identiquement partout.

7. **Point de montage du seed (`/seed` vs `/mnt`) — déjà correct ici, à garder**
   Ce point était correctement géré dans le script actuel (`/seed`, pas `/mnt`).
   Aucune action requise, mais **à documenter explicitement comme convention à
   ne jamais casser**, car KB-003 (pipeline NetPulse, autre repo) utilise `/mnt`
   pour la même chose et une fusion future des deux méthodologies devra trancher
   une convention commune.

## Défauts liés au boot EFI (contexte, déjà résolus manuellement en session)

8. **`--efidisk0` manquant lors de la création manuelle de VM**
   Sans NVRAM persistant, le comportement au boot OVMF est instable. Résolu en
   session en l'ajoutant explicitement à la commande `qm create`/`qm set`.
   → Si un script de création de VM existe ou est prévu (`create-vm-real` via
   `just`), vérifier qu'il inclut systématiquement `--efidisk0`. Sinon, l'ajouter
   à la documentation de création de VM comme paramètre non-optionnel.

---

## Ce qui est demandé à l'agent

1. Lire le repo `client-leger-guacamole` en entier (flake, modules, scripts, docs)
   pour localiser précisément où chacun des 8 points ci-dessus doit être corrigé.
2. Appliquer les corrections dans le flake et les scripts concernés.
3. **Retester la procédure complète de bout en bout sur une VM de test** (pas 133,
   utiliser un VMID de test dédié — 134 ou suivant), en suivant exactement les
   3 moments :
   - Moment 1 (Proxmox) : création VM avec `--efidisk0`, seed avec clé age incluse
     (échec dur si absente, point 4)
   - Moment 2 (LiveBoot) : sélection console série manuelle (documentée comme
     étape obligatoire, non scriptable sans contrôleur console — ne pas essayer
     de l'automatiser dans cette mission), puis `guacamole-live-install.sh`
   - Moment 3 (Proxmox) : `guacamole-finalize.sh`, vérifier IP détectée
     automatiquement (point 2), SSH fonctionnel immédiatement (point 3), sops
     déchiffré sans intervention manuelle (point 4)
4. Documenter chaque point corrigé avec le **avant/après** (extrait de config ou
   de script modifié) dans un rapport de session, format
   `_rapports-session/rapport-YYYY-MM-DD.md` si le repo mynix est accessible à
   l'agent, sinon dans un `RAPPORT-fix-pipeline.md` à la racine du repo
   `client-leger-guacamole`.
5. Ne pas déclarer la procédure "finale" tant que le test de bout en bout du
   point 3 n'a pas réussi sans aucune intervention manuelle de rattrapage.

## Livrable attendu en retour

- Diff ou liste des fichiers modifiés dans `client-leger-guacamole`.
- Rapport de test end-to-end (succès/échec par étape des 3 moments).
- Toute nouvelle friction découverte pendant le retest, même mineure — à ajouter
  à cette liste plutôt qu'à corriger silencieusement, pour qu'elle soit intégrée
  à la fusion documentaire finale (KB-003 + procédure 3-moments + ce repo).
