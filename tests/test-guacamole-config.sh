#!/usr/bin/env bash
# =============================================================================
# test-guacamole-config.sh — vérifications LOCALES du repo guacamole.
# Ne touche pas à l'infra existante.
# =============================================================================
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'
ok()  { echo -e "${GREEN}[OK]${NC}  $*"; }
fail(){ echo -e "${RED}[FAIL]${NC} $*"; }
warn(){ echo -e "${YELLOW}[WARN]${NC} $*"; }
FAILS=0

# 1. Le flake évalue (config NixOS guacamole).
echo "── 1. nix flake check ───────────────────────────────"
if nix flake check --no-build 2>/dev/null; then
  ok "flake évalue sans erreur (--no-build)"
else
  warn "flake check --no-build non concluant (réseau/évaluation) — réessai complet"
  if nix flake check 2>&1; then ok "flake check OK"; else fail "flake check en échec"; FAILS=$((FAILS+1)); fi
fi

# 2. Aucun secret plaintext committé.
echo "── 2. Secrets ───────────────────────────────────────"
# Seuls sont autorisés dans secrets/ : *.age (chiffrés), *.example et README.md.
BAD_SECRETS=$(git ls-files 'secrets/*' | grep -Ev '\.(age|example)$|README\.md' || true)
if [[ -n "$BAD_SECRETS" ]]; then
  fail "Fichiers secrets/ suspects suivis par git :"
  echo "$BAD_SECRETS" | sed 's/^/    /'
  FAILS=$((FAILS+1))
else
  ok "secrets/ ne contient que .age / .example / README.md"
fi
if git ls-files | grep -q 'user-mapping.xml$'; then
  fail "secrets/user-mapping.xml (plaintext) suivi par git"
  FAILS=$((FAILS+1))
else
  ok "pas de user-mapping.xml plaintext dans git"
fi

# 3. Le placeholder de clé admin doit être remplacé avant déploiement.
echo "── 3. Clé admin placeholder ─────────────────────────"
if grep -q "PLACEHOLDER_ADMIN_KEY" nixos/hosts/guacamole/default.nix; then
  warn "clé admin = PLACEHOLDER — à remplacer (docs/DEPLOYMENT.md) avant déploiement"
else
  ok "clé admin configurée"
fi

# 4. La config ne dual-home pas la VM (une seule carte, vmbr0).
echo "── 4. Absence de dual-homing ────────────────────────"
if grep -q "vmbr1\|vmbr2" nixos/modules/guacamole.nix; then
  fail "Référence à vmbr1/vmbr2 dans le module réseau (pont interdit)"
  FAILS=$((FAILS+1))
else
  ok "aucune référence vmbr1/vmbr2 dans le module réseau"
fi

echo ""
if [[ $FAILS -eq 0 ]]; then
  echo -e "${GREEN}✅ Tous les tests locaux passent.${NC}"
else
  echo -e "${RED}❌ $FAILS échec(s).${NC}"
  exit 1
fi
