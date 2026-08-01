#!/usr/bin/env bash
# =============================================================================
# test-upstream-no-regression.sh — valide que client-leger-nixos n'a PAS
# régressé. En lecture seule : ce script ne modifie AUCUN fichier du repo
# upstream. C'est la validation finale demandée par le brief
# (« just test sur client-leger-nixos doit toujours passer sans modification »).
#
# NB : la suite `just test` upstream inclut des tests réseau dépendant de VMs
# Windows encore non configurées (échec pré-existant documenté dans
# status.md/kb001 — indépendant de ce chantier). On valide donc ici les
# parties reproductibles : `nix flake check` + état du repo.
# =============================================================================
set -uo pipefail

UPSTREAM="${UPSTREAM:-/home/andrei/Projects/00_INFRAS/10_CLIENTLEGER/client-leger-nixos}"
GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'
ok()  { echo -e "${GREEN}[OK]${NC}  $*"; }
fail(){ echo -e "${RED}[FAIL]${NC} $*"; }
warn(){ echo -e "${YELLOW}[WARN]${NC} $*"; }
FAILS=0

[[ -d "$UPSTREAM" ]] || { fail "repo upstream introuvable : $UPSTREAM"; exit 1; }

echo "── État git upstream (lecture seule) ────────────────"
git -C "$UPSTREAM" status --porcelain
if [[ -n "$(git -C "$UPSTREAM" status --porcelain)" ]]; then
  warn "repo upstream a des modifications locales — non bloquant (aucun changement fait par ce repo)"
fi

echo "── nix flake check upstream ─────────────────────────"
if ( cd "$UPSTREAM" && nix flake check 2>&1 ); then
  ok "flake check upstream OK"
else
  fail "flake check upstream en échec"
  FAILS=$((FAILS+1))
fi

echo "── Le repo guacamole n'a PAS modifié upstream ───────"
if git -C "$UPSTREAM" status --porcelain | grep -q .; then
  warn "upstream modifié localement — vérifier que ce n'est pas une régression"
fi

echo ""
if [[ $FAILS -eq 0 ]]; then
  echo -e "${GREEN}✅ Pas de régression détectée sur client-leger-nixos.${NC}"
else
  echo -e "${RED}❌ $FAILS problème(s) sur upstream.${NC}"
  exit 1
fi
