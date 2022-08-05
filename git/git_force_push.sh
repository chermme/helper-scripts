#!/bin/zsh

YELLOW='\033[1;33m'
NC='\033[0m' # No Color

CURRENT_BRANCH_NAME=$(git rev-parse --abbrev-ref HEAD)
source ~/.zshrc
backup-branch
echo >&2 "${YELLOW}Force pushing branch '"$CURRENT_BRANCH_NAME"'${NC}"
git push --force
