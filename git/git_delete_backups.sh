#!/bin/zsh
BACKUP_BRANCHES=($(git for-each-ref --format='%(refname)' refs/heads | cut -d/ -f3- | grep "backup/"))
CURRENT_BRANCH_NAME=$(git rev-parse --abbrev-ref HEAD)

YELLOW='\033[1;33m'
NC='\033[0m' # No Color

for BRANCH in ${BACKUP_BRANCHES[@]}; do
  echo "${YELLOW}Deleting backup branch $BRANCH...${NC}"
  if [[ $CURRENT_BRANCH_NAME != $BRANCH ]]; then
	  git branch -D $BRANCH
  fi
done