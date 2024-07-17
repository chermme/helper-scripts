PR_NUMBER=$1

SOURCE_REPO=thedrawingroom/hss-ux-components
SOURCE_REPO_PATH=$HOME/Git/tdr/hss-ux-components

DEST_REPO=HSS-Proservice/react-ux
DEST_REPO_PATH=$HOME/Git/hss/react-ux

if [ -z "$PR_NUMBER" ]; then
  echo "PR_NUMBER is not provided. Exiting..."
  exit 1
fi

CHANGED_FILES=$(gh pr view $PR_NUMBER --repo $SOURCE_REPO --json files --jq '.files[].path')
PR_BRANCH_NAME=$(gh pr view $PR_NUMBER --repo $SOURCE_REPO --json headRefName --jq '.headRefName')

# git checkout PR branch
cd $SOURCE_REPO_PATH
git checkout $PR_BRANCH_NAME

# create a new branch in the destination repo
MASTER_BRANCH_NAME=$(gh api repos/$DEST_REPO --jq '.default_branch')
cd $DEST_REPO_PATH
git checkout $MASTER_BRANCH_NAME
git checkout -b sync/$PR_BRANCH_NAME

for file in $CHANGED_FILES; do
  echo "Copying $SOURCE_REPO_PATH/$file to $DEST_REPO_PATH"
  cp $SOURCE_REPO_PATH/$file $DEST_REPO_PATH/$file
done
