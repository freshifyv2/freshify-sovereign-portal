#!/usr/bin/env bash
# Sovereign Portal — clone the seven component repos as siblings of this one.
#
# Usage (from inside freshify-sovereign-portal/):
#   ./scripts/clone-all.sh
#
# Result: every component repo ends up next to this one, ready for
# `docker compose up --build`.
#
#   parent-dir/
#   ├── freshify-sovereign-portal/   (this repo)
#   ├── freshify-portal-shell/
#   ├── freshify-users/
#   ├── freshify-users-fe/
#   ├── freshify-companies/
#   ├── freshify-companies-fe/
#   ├── freshify-workspaces/
#   └── freshify-workspaces-fe/
#
# Re-run safely: existing clones are pulled instead of re-cloned.

set -euo pipefail

ORG="freshifyv2"
GIT_BASE="${GIT_BASE:-https://github.com/${ORG}}"

REPOS=(
  freshify-portal-shell
  freshify-portal-shell-ui
  freshify-users
  freshify-users-fe
  freshify-companies
  freshify-companies-fe
  freshify-workspaces
  freshify-workspaces-fe
)

# Resolve the parent of this repo so the script works no matter where it's
# invoked from.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
META_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
PARENT_DIR="$(cd "${META_DIR}/.." && pwd)"

echo "Sovereign Portal — cloning component repos into:"
echo "  ${PARENT_DIR}"
echo ""

cd "${PARENT_DIR}"

for repo in "${REPOS[@]}"; do
  if [ -d "${repo}/.git" ]; then
    echo "── ${repo} (exists) ──"
    git -C "${repo}" pull --ff-only --quiet || {
      echo "  warning: could not fast-forward ${repo} — leaving as is"
    }
  else
    echo "── ${repo} (cloning) ──"
    git clone --quiet "${GIT_BASE}/${repo}.git" "${repo}"
  fi
done

echo ""
echo "Done. Next:"
echo "  cd ${META_DIR##*/}"
echo "  cp .env.example .env   # if you haven't already"
echo "  docker compose up --build"
echo ""
echo "Then open http://localhost:3000"
