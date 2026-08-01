# Secrets

Ce dossier contient UNIQUEMENT des fichiers chiffrés (sops/age) et des
exemples plaintext clairement identifiés.

## Fichiers

| Fichier | Contenu | Chiffré |
|---------|---------|---------|
| `user-mapping.xml.age` | user-mapping Guacamole (comptes + connexions RDP + mots de passe Windows) | ✅ |
| `user-mapping.xml.example` | Template plaintext pour créer le fichier ci-dessus | ❌ (placeholder) |

## Créer `user-mapping.xml.age`

Prérequis : clé age privée sur la machine de contrôle
(`~/.config/sops/age/keys.txt`), identique à celle de `client-leger-nixos`.

```bash
cp secrets/user-mapping.xml.example secrets/user-mapping.xml
$EDITOR secrets/user-mapping.xml     # vrais comptes, vrais mdp, IPs de connexion
sops -e -i secrets/user-mapping.xml  # chiffre le fichier en place
mv secrets/user-mapping.xml secrets/user-mapping.xml.age
rm -f secrets/user-mapping.xml       # ne JAMAIS laisser le plaintext
```

Le secret est ensuite décrypté sur la VM au boot par `sops-nix` vers
`/etc/guacamole/user-mapping.xml` (module `nixos/modules/secrets.nix`).

> ⚠️ Si `user-mapping.xml.age` est absent, le flake évalue quand même
> (le secret est déclaré conditionnellement) mais Guacamole n'a aucun compte :
> le login est impossible tant que le secret n'est pas créé.
