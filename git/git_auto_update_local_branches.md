# Git Auto Update Local Branches

A bash script that automatically updates all your local Git branches by merging changes from the main branch. It includes special support for "stacked" branches (branches built on top of other feature branches).

## Features

- ✅ Automatically updates all local branches with latest changes from main
- ✅ Handles stacked branches with intelligent rebasing
- ✅ Excludes specified branch patterns and GitHub PR labels
- ✅ **Dry-run mode** to preview changes before applying
- ✅ **No-push mode** to update locally without pushing to remote
- ✅ **Verbose mode** for detailed debugging output
- ✅ Comprehensive error handling and conflict detection
- ✅ Clean separation of merge vs rebase conflicts
- ✅ Automatic npm install when dependencies change

## Usage

### Basic Usage

```bash
# Update all branches (uses 'main' as the default branch)
./git_auto_update_local_branches.sh

# Use a different main branch
./git_auto_update_local_branches.sh develop
```

### Dry-Run Mode

Preview what would happen without making any changes. No local or remote changes will be made.

```bash
DRY_RUN=true ./git_auto_update_local_branches.sh
```

### No-Push Mode

Update all branches locally but do not push to the remote repository. This is useful when you want to review all changes before pushing.

```bash
NO_PUSH=true ./git_auto_update_local_branches.sh
```

### Verbose Mode

By default, the script silences the output of `git` and `gh` commands to keep the summary clean. Use `VERBOSE` mode to see the detailed output for debugging.

```bash
VERBOSE=true ./git_auto_update_local_branches.sh
```

## How It Works

### Phase 1: Regular Branches

The script processes all non-stacked branches first:

1. Fetches latest changes from remote.
2. Updates the `main` branch by pulling the latest changes.
3. For each regular branch:
   - Checks out the branch.
   - Pulls latest changes for the branch.
   - Merges `main` into the branch.
   - Pushes changes to the remote.

### Phase 2: Stacked Branches

Stacked branches follow the naming convention: `stacked/parent-ticket/branch-name`

Example: `stacked/br4565/BR-4596-my-feature`

The script handles stacked branches intelligently:

1. **Sorts by dependencies**: Processes parent branches before their children.
2. **Checks parent status**:
   - If parent branch **exists**: Rebases the stacked branch onto the parent.
   - If parent **merged to main**: Merges `main` into the stacked branch.
   - If parent **not found**: Falls back to merging `main`.

### Stacked Branch Examples

```bash
# Parent branch
BR-1234-authentication

# Stacked branch built on top
stacked/br1234/BR-5678-user-profile
```

**Important**: The parent ticket reference (`br1234`) is case-insensitive and ignores hyphens/underscores.

Valid matches:

- `BR-1234-feature` matches `stacked/br1234/...`
- `br_1234_feature` matches `stacked/BR1234/...`
- `Br1234Feature` matches `stacked/br-1234/...`

## Configuration

You can configure the script by editing the variables at the top of the file or by setting environment variables when you run it.

```bash
# --- Script Configuration ---
MAIN_BRANCH="${1:-main}"
EXCLUDED_BRANCHES=("backup/" "temp/" "archive/")
EXCLUDED_GH_LABELS=("mergequeue")

# --- Environment Variables ---
DRY_RUN="${DRY_RUN:-false}"
NO_PUSH="${NO_PUSH:-false}"
VERBOSE="${VERBOSE:-false}"
```

### Excluding Branches

Branches are excluded if they:

- Match any pattern in `EXCLUDED_BRANCHES`.
- Are the `main` branch itself.
- Have a GitHub PR with any label in `EXCLUDED_GH_LABELS` (requires `gh` CLI).

## Output Summary

After processing, the script displays:

1. **Ignored branches**: Excluded based on patterns or labels.
2. **Updated branches**: Successfully merged and pushed.
3. **Rebased stacked branches**: Successfully rebased (require manual force-push).
4. **Branches with merge conflicts**: Need manual conflict resolution.
5. **Branches with rebase conflicts**: Need manual conflict resolution.
6. **Branches that failed**: Other errors occurred.

### Rebased Branches

Rebased branches are **not automatically force-pushed** for safety. You must manually push them:

```bash
git push --force-with-lease origin branch-name
```

The script will show you the exact commands to run.

## Exit Codes

- `0`: Success (all branches processed without conflicts).
- `1`: One or more branches failed to process due to an error.
- `10`: One or more branches have merge or rebase conflicts that require manual resolution.

## Requirements

### Required

- Git
- Bash 4.0+ (for associative arrays). The script uses `#!/usr/bin/env bash` to find the latest version in your `PATH`.

### Optional

- **GitHub CLI (`gh`)**: For checking PR labels.
- **jq**: For parsing GitHub CLI output.
- **npm**: For automatic dependency updates if `package.json` changes are detected.

If optional tools are not installed, the script will skip related features and continue.

## Error Handling

The script includes comprehensive error handling:

- ✅ Detects uncommitted changes before processing.
- ✅ Aborts merges/rebases on conflict and cleans up.
- ✅ Validates stacked branch naming format.
- ✅ Handles missing remote branches.
- ✅ Returns to your original branch on completion.
- ✅ Verifies the working directory is clean after operations.

## Stacked Branch Workflow

### Creating a Stacked Branch

1. Create your parent feature branch normally:

   ```bash
   git checkout -b BR-1234-parent-feature
   ```

2. Create a stacked branch on top, referencing the parent's ticket number:

   ```bash
   git checkout -b stacked/br1234/BR-5678-child-feature
   ```

### What Happens During Update

**Scenario 1**: Parent branch still exists.

```text
stacked/br1234/BR-5678 rebased onto BR-1234-parent-feature
(Manual force-push required)
```

**Scenario 2**: Parent has been merged to main.

```text
stacked/br1234/BR-5678 merged with main
(Automatically pushed)
```

**Scenario 3**: Parent was deleted/not found.

```text
stacked/br1234/BR-5678 merged with main
(Automatically pushed)
```

## Common Issues

### Invalid Stacked Branch Format

**Error**: `Invalid stacked branch format: stacked/BR-1234-feature`

**Solution**: Stacked branches must have three parts: `stacked/parent-ticket/branch-name`.

```bash
# Wrong
stacked/BR-1234-feature

# Correct
stacked/br1234/BR-1234-feature
```

### Parent Branch Not Found

If the parent branch can't be found, the script will automatically fall back to merging from `main`. This is normal when the parent has been merged and deleted.

### Merge/Rebase Conflicts

The script detects and aborts conflicting operations. You'll need to:

1. Manually check out the branch.
2. Resolve the conflicts.
3. Run the script again (it will skip already-updated branches).

## Tips

- Run in **dry-run mode** first to preview changes.
- Ensure your working directory is clean before running.
- Stacked branches are processed in dependency order automatically.
- The script is safe to re-run—it skips branches that are already up-to-date.
- Force-push rebased branches carefully after reviewing changes.

## Examples

### Update all branches with dry-run

```bash
DRY_RUN=true ./git_auto_update_local_branches.sh
```

### Update locally without pushing

```bash
NO_PUSH=true ./git_auto_update_local_branches.sh
```

### See detailed output for debugging

```bash
VERBOSE=true ./git_auto_update_local_branches.sh
```

### Update using 'develop' as main branch

```bash
./git_auto_update_local_branches.sh develop
```

### Combine dry-run and no-push

```bash
DRY_RUN=true NO_PUSH=true ./git_auto_update_local_branches.sh
```

### Exclude additional patterns

Edit the script to add more exclusions:

```bash
EXCLUDED_BRANCHES=("backup/" "temp/" "archive/" "experimental/")
```

### After running the script

```bash
# Force-push a rebased stacked branch
git push --force-with-lease origin stacked/br1234/BR-5678-feature

# Resolve conflicts manually for failed branches
git checkout BR-1234-feature
git merge main
# ... resolve conflicts ...
git push
```
