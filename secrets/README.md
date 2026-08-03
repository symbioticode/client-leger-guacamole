# Secrets

Ce dossier contient UNIQUEMENT des fichiers chiffrés (sops/age), l'exemple
plaintext correspondant et ce README. Le plaintext de travail
(`user-mapping.json`) est gitignoré.

## Fichiers

| Fichier | Contenu | Chiffré |
|---------|---------|---------|
| `user-mapping.json.age` | secret sops nommé `user-mapping.xml` (user-mapping Guacamole : comptes + connexions RDP + mots de passe Windows) | ✅ |
| `user-mapping.json.example` | Template plaintext pour créer `user-mapping.json` | ❌ (placeholder) |
| `user-mapping.json` | Plaintext de travail (gitignoré) — sert uniquement à régénérer le `.age` | ❌ (gitignoré) |

> ⚠️ Pourquoi `.json` et pas `.xml` ? Le champ est déclaré dans sops-nix sous
> la clé `user-mapping.xml`. `sops -e secrets/user-mapping.xml` (extension
> inconnue de sops) produit un blob `data` que `sops-install-secrets` ne sait
> pas associer à la clé → erreur `the key 'user-mapping.xml' cannot be found`.
> En encapsulant le XML dans un JSON `{"user-mapping.xml": "<xml>"}`, les clés
> top-level du `.age` sont `['user-mapping.xml', 'sops']` et le secret se lit.

## Créer / mettre à jour `user-mapping.json.age`

Prérequis : clé age privée sur la machine de contrôle
(`~/.config/sops/age/keys.txt`), identique à celle de `client-leger-nixos`.

```bash
cp secrets/user-mapping.json.example secrets/user-mapping.json
$EDITOR secrets/user-mapping.json        # vrais comptes, vrais mdp, IPs
sops -e --input-type json --output-type json \
  secrets/user-mapping.json > secrets/user-mapping.json.age
```

Ou via `just encrypt-user-mapping` (même chose, éditeur par défaut).

Vérification (roundtrip) :

```bash
sops -d --input-type json --output-type json secrets/user-mapping.json.age \
  | python3 -c 'import json,sys; print(json.load(sys.stdin)["user-mapping.xml"])'
```

Le secret est décrypté sur la VM au boot par `sops-nix` vers
`/etc/guacamole/user-mapping.xml` (module `nixos/modules/secrets.nix`).

> ⚠️ Si `user-mapping.json.age` est absent, le flake évalue quand même
> (le secret est déclaré conditionnellement) mais Guacamole n'a aucun compte :
> le login est impossible tant que le secret n'est pas créé.
