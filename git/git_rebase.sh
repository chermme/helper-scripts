#!/bin/zsh

YELLOW='\033[1;33m'
NC='\033[0m' # No Color

CURRENT_BRANCH_NAME=$(git rev-parse --abbrev-ref HEAD)
PARENT_BRANCH_NAME=$(git show-branch | grep '*' | grep -v "$(git rev-parse --abbrev-ref HEAD)" | head -n1 | sed 's/.*\[\(.*\)\].*/\1/' | sed 's/[\^~].*//')

# Make sure we don't make a backup branch repeatedly
if [[ $CURRENT_BRANCH_NAME == backup* ]]; then
	echo >&2 "${YELLOW}Branch '"$CURRENT_BRANCH_NAME"' is already a backup${NC}"
	exit 1
fi

BACKUP_BRANCH_NAME="backup/$(date +%Y-%m-%d__%H-%M-%S)/$CURRENT_BRANCH_NAME"

git branch $BACKUP_BRANCH_NAME

echo "${YELLOW}Current branch has been backed up as: $BACKUP_BRANCH_NAME${NC}"
echo "${YELLOW}Rebasing onto parent branch >>$PARENT_BRANCH_NAME<<${NC}"

git pull origin $PARENT_BRANCH_NAME --rebase
