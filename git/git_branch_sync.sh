#!/bin/bash
# Git Branch Sync System
# Automatically tracks and syncs your Git branches across machines

SYNC_DIR="$HOME/.git-workspaces"
SCRIPT_ZSH_ALIAS="git-branch-sync"

# Git hooks to temporarily deactivate during operations
HOOKS_TO_DEACTIVATE=("post-checkout" "post-merge" "pre-commit")

# Branch patterns to ignore during restore (branches matching these patterns will be skipped)
IGNORED_BRANCH_PATTERNS=("backup/")

# Track deactivated hooks for cleanup
DEACTIVATED_HOOKS=()

# Track ignored branches during restore
IGNORED_BRANCHES=()

# Get the absolute path to this script
if [ -n "${BASH_SOURCE[0]}" ]; then
    SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
else
    SCRIPT_PATH="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
fi

# ============================================================================
# Get unique identifier for repo based on remote URL
# ============================================================================
get_repo_id() {
    # Try to get remote URL (origin first, then any remote)
    REMOTE_URL=$(git config --get remote.origin.url 2>/dev/null)
    
    if [ -z "$REMOTE_URL" ]; then
        # No origin, try to find any remote
        REMOTE_URL=$(git remote -v | head -n1 | awk '{print $2}')
    fi
    
    if [ -z "$REMOTE_URL" ]; then
        # No remotes at all - fall back to repo root path
        echo "$(git rev-parse --show-toplevel 2>/dev/null)"
        return
    fi
    
    # Normalize the URL to create a safe filename
    # Remove protocol, replace special chars with underscores
    REPO_ID=$(echo "$REMOTE_URL" | sed -e 's|^.*://||' -e 's|^git@||' -e 's|:|/|' -e 's|\.git$||' -e 's|[^a-zA-Z0-9/_-]|_|g')
    echo "$REPO_ID"
}

# ============================================================================
# Branch Filtering
# ============================================================================

# Check if a branch should be ignored based on IGNORED_BRANCH_PATTERNS
should_ignore_branch() {
    local branch="$1"
    
    for pattern in "${IGNORED_BRANCH_PATTERNS[@]}"; do
        if [[ "$branch" == *"$pattern"* ]]; then
            return 0  # Should ignore (pattern matches)
        fi
    done
    
    return 1  # Should not ignore (no pattern matches)
}

# ============================================================================
# Git Hooks Management
# ============================================================================

# Deactivate git hooks by renaming them
deactivate_git_hooks() {
    local git_hooks_dir=".git/hooks"
    
    if [ ! -d "$git_hooks_dir" ]; then
        return 0
    fi
    
    echo "Deactivating git hooks..."
    
    for hook in "${HOOKS_TO_DEACTIVATE[@]}"; do
        local hook_path="$git_hooks_dir/$hook"
        local disabled_path="$git_hooks_dir/$hook.disabled"
        
        if [ -f "$hook_path" ] && [ ! -f "$disabled_path" ]; then
            if mv "$hook_path" "$disabled_path" 2>/dev/null; then
                DEACTIVATED_HOOKS+=("$hook")
            fi
        fi
    done
}

# Reactivate git hooks by renaming them back
reactivate_git_hooks() {
    local git_hooks_dir=".git/hooks"
    
    if [ ${#DEACTIVATED_HOOKS[@]} -eq 0 ]; then
        return 0
    fi
    
    echo "Reactivating git hooks..."
    
    for hook in "${DEACTIVATED_HOOKS[@]}"; do
        local hook_path="$git_hooks_dir/$hook"
        local disabled_path="$git_hooks_dir/$hook.disabled"
        
        if [ -f "$disabled_path" ]; then
            mv "$disabled_path" "$hook_path" 2>/dev/null
        fi
    done
    
    DEACTIVATED_HOOKS=()
}

# Cleanup function to ensure hooks are reactivated on exit
cleanup_on_exit() {
    reactivate_git_hooks
}

# ============================================================================
# Core save function - called by Git hooks
# ============================================================================
save_workspace() {
    REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null)
    if [ -z "$REPO_ROOT" ]; then
        echo "Error: Not in a Git repository"
        exit 1
    fi

    REPO_ID=$(get_repo_id)
    if [ -z "$REPO_ID" ]; then
        echo "Error: Could not determine repository identifier"
        exit 1
    fi

    # Create workspace path based on repo ID
    WORKSPACE_PATH="$SYNC_DIR/$REPO_ID"
    mkdir -p "$WORKSPACE_PATH"
    
    WORKSPACE_FILE="$WORKSPACE_PATH/.git-workspace"
    CURRENT=$(git branch --show-current)
    ALL_BRANCHES=$(git branch --format='%(refname:short)')
    REMOTE_URL=$(git config --get remote.origin.url 2>/dev/null)

    # Filter out ignored branches
    BRANCHES=()
    while IFS= read -r branch; do
        if ! should_ignore_branch "$branch"; then
            BRANCHES+=("$branch")
        fi
    done <<< "$ALL_BRANCHES"

    cat > "$WORKSPACE_FILE" <<EOF
repo_path=$REPO_ROOT
remote_url=$REMOTE_URL
current_branch=$CURRENT
updated=$(date -u +"%Y-%m-%d %H:%M:%S UTC")

# Branches (one per line)
EOF

    printf "%s\n" "${BRANCHES[@]}" >> "$WORKSPACE_FILE"
    
    echo "✓ Workspace saved: $WORKSPACE_FILE"
}

# ============================================================================
# Restore workspace for current repo
# ============================================================================
restore_workspace() {
    # Set up trap to ensure hooks are reactivated on exit
    trap cleanup_on_exit EXIT
    
    REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null)
    if [ -z "$REPO_ROOT" ]; then
        echo "Error: Not in a Git repository"
        exit 1
    fi

    REPO_ID=$(get_repo_id)
    if [ -z "$REPO_ID" ]; then
        echo "Error: Could not determine repository identifier"
        exit 1
    fi

    WORKSPACE_PATH="$SYNC_DIR/$REPO_ID"
    WORKSPACE_FILE="$WORKSPACE_PATH/.git-workspace"

    if [ ! -f "$WORKSPACE_FILE" ]; then
        echo "No workspace file found for this repo"
        echo "Repository ID: $REPO_ID"
        echo "Expected: $WORKSPACE_FILE"
        exit 1
    fi

    echo "Restoring workspace from: $WORKSPACE_FILE"
    
    # Read the file
    CURRENT_BRANCH=""
    BRANCHES=()
    IN_BRANCHES=false
    
    while IFS= read -r line; do
        if [[ "$line" =~ ^current_branch=(.*)$ ]]; then
            CURRENT_BRANCH="${BASH_REMATCH[1]}"
        elif [[ "$line" =~ ^# ]]; then
            IN_BRANCHES=true
        elif [ "$IN_BRANCHES" = true ] && [ -n "$line" ]; then
            BRANCHES+=("$line")
        fi
    done < "$WORKSPACE_FILE"

    echo "Found ${#BRANCHES[@]} branches to restore"
    
    # Deactivate git hooks before operations
    deactivate_git_hooks
    
    # Fetch from all remotes
    echo "Fetching from remotes..."
    git fetch --all --quiet

    # Restore each branch
    for branch in "${BRANCHES[@]}"; do
        # Skip ignored branches based on patterns
        if should_ignore_branch "$branch"; then
            IGNORED_BRANCHES+=("$branch")
            echo "  ⊘ $branch (ignored - matches pattern)"
            continue
        fi
        
        # Skip branches that don't exist in origin (local-only branches)
        if ! git show-ref --verify --quiet "refs/remotes/origin/$branch"; then
            IGNORED_BRANCHES+=("$branch")
            echo "  ⊘ $branch (ignored - not in origin)"
            continue
        fi
        
        if git show-ref --verify --quiet "refs/heads/$branch"; then
            # Branch exists locally, update it from origin
            git checkout "$branch" --quiet 2>/dev/null
            PULL_OUTPUT=$(git pull --quiet origin "$branch" 2>&1)
            PULL_STATUS=$?
            if [ $PULL_STATUS -eq 0 ]; then
                if [[ "$PULL_OUTPUT" == *"Already up to date"* ]]; then
                    echo "  ✓ $branch (already up-to-date)"
                else
                    echo "  ✓ $branch (updated from origin)"
                fi
            else
                echo "  ⚠ $branch (pull failed - may have conflicts)"
            fi
        else
            # Branch doesn't exist locally, create it from origin
            git checkout -b "$branch" "origin/$branch" --quiet 2>/dev/null
            echo "  ✓ $branch (created from origin)"
        fi
    done

    # Checkout the current branch
    if [ -n "$CURRENT_BRANCH" ] && git show-ref --verify --quiet "refs/heads/$CURRENT_BRANCH"; then
        git checkout "$CURRENT_BRANCH" --quiet
        echo ""
        echo "✓ Restored to branch: $CURRENT_BRANCH"
    fi
    
    # Show summary of ignored branches if any
    if [ ${#IGNORED_BRANCHES[@]} -gt 0 ]; then
        echo ""
        echo "Ignored ${#IGNORED_BRANCHES[@]} branch(es) matching patterns: ${IGNORED_BRANCH_PATTERNS[*]}"
    fi

    # Check for local branches not in workspace file
    echo ""
    echo "Checking for branches not in workspace file..."
    
    # Get all local branches
    ALL_LOCAL_BRANCHES=($(git branch --format='%(refname:short)'))
    
    # Find branches not in workspace file
    EXTRA_BRANCHES=()
    for local_branch in "${ALL_LOCAL_BRANCHES[@]}"; do
        found=false
        for workspace_branch in "${BRANCHES[@]}"; do
            if [ "$local_branch" = "$workspace_branch" ]; then
                found=true
                break
            fi
        done
        if [ "$found" = false ]; then
            EXTRA_BRANCHES+=("$local_branch")
        fi
    done
    
    if [ ${#EXTRA_BRANCHES[@]} -eq 0 ]; then
        echo "  No extra branches found"
    else
        echo "  Found ${#EXTRA_BRANCHES[@]} branch(es) not in workspace file:"
        echo ""
        
        for branch in "${EXTRA_BRANCHES[@]}"; do
            # Check if branch exists in remote origin
            if ! git show-ref --verify --quiet "refs/remotes/origin/$branch"; then
                echo "  ℹ  $branch (not in remote origin - skipping)"
                continue
            fi
            
            # Check if branch is ahead, behind, or up-to-date with origin
            LOCAL_HASH=$(git rev-parse "$branch" 2>/dev/null)
            REMOTE_HASH=$(git rev-parse "origin/$branch" 2>/dev/null)
            
            if [ "$LOCAL_HASH" = "$REMOTE_HASH" ]; then
                STATUS="up-to-date with origin"
            else
                AHEAD=$(git rev-list --count "origin/$branch..$branch" 2>/dev/null || echo "0")
                BEHIND=$(git rev-list --count "$branch..origin/$branch" 2>/dev/null || echo "0")
                
                if [ "$AHEAD" -gt 0 ]; then
                    echo "  ℹ  $branch (ahead of origin by $AHEAD commit(s) - skipping)"
                    continue
                fi
                
                if [ "$BEHIND" -gt 0 ]; then
                    STATUS="behind origin by $BEHIND commit(s)"
                else
                    STATUS="up-to-date with origin"
                fi
            fi
            
            # Offer to delete the branch
            echo "  Branch: $branch"
            echo "  Status: $STATUS"
            read -p "  Delete this branch? (y/N): " -n 1 -r
            echo ""
            
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                # Don't delete if it's currently checked out
                CURRENT_CHECKED_OUT=$(git branch --show-current)
                if [ "$branch" = "$CURRENT_CHECKED_OUT" ]; then
                    echo "    ✗ Cannot delete currently checked out branch"
                else
                    git branch -d "$branch" 2>/dev/null
                    if [ $? -eq 0 ]; then
                        echo "    ✓ Deleted $branch"
                    else
                        echo "    ✗ Failed to delete $branch (use 'git branch -D $branch' to force)"
                    fi
                fi
            else
                echo "    Skipped"
            fi
            echo ""
        done
    fi
    
    # Reactivate git hooks
    reactivate_git_hooks
}

# ============================================================================
# List all tracked workspaces
# ============================================================================
list_workspaces() {
    if [ ! -d "$SYNC_DIR" ]; then
        echo "No workspaces tracked yet"
        exit 0
    fi

    echo "Tracked workspaces:"
    echo ""
    
    find "$SYNC_DIR" -name ".git-workspace" -type f | while read -r workspace; do
        REPO_PATH=$(grep "^repo_path=" "$workspace" | cut -d= -f2)
        REMOTE_URL=$(grep "^remote_url=" "$workspace" | cut -d= -f2)
        CURRENT=$(grep "^current_branch=" "$workspace" | cut -d= -f2)
        UPDATED=$(grep "^updated=" "$workspace" | cut -d= -f2)
        BRANCH_COUNT=$(grep -v "^repo_path=\|^remote_url=\|^current_branch=\|^updated=\|^#\|^$" "$workspace" | wc -l)
        
        echo "Remote: $REMOTE_URL"
        echo "  Local path: $REPO_PATH"
        echo "  Current branch: $CURRENT"
        echo "  Branches tracked: $BRANCH_COUNT"
        echo "  Last updated: $UPDATED"
        echo ""
    done
}

# ============================================================================
# Show repository ID for current repo
# ============================================================================
show_repo_id() {
    REPO_ID=$(get_repo_id)
    REMOTE_URL=$(git config --get remote.origin.url 2>/dev/null)
    
    echo "Repository ID: $REPO_ID"
    echo "Remote URL: $REMOTE_URL"
    echo "Workspace file: $SYNC_DIR/$REPO_ID/.git-workspace"
}

# ============================================================================
# Install Git hooks
# ============================================================================
install_hooks() {
    local HOOKS_DIR="${1:-$HOME/.git-templates/hooks}"
    local IS_GLOBAL="${2:-true}"
    
    mkdir -p "$HOOKS_DIR"

    # Create post-checkout hook
    cat > "$HOOKS_DIR/post-checkout" <<HOOK_EOF
#!/bin/bash
# Auto-save workspace on branch checkout
"$SCRIPT_PATH" save
HOOK_EOF

    # Create post-commit hook
    cat > "$HOOKS_DIR/post-commit" <<HOOK_EOF
#!/bin/bash
# Auto-save workspace on commit (catches new branches)
"$SCRIPT_PATH" save
HOOK_EOF

    chmod +x "$HOOKS_DIR/post-checkout" "$HOOKS_DIR/post-commit"

    if [ "$IS_GLOBAL" = true ]; then
        # Configure Git to use this template
        git config --global init.templateDir "$HOME/.git-templates"

        echo "✓ Git hooks installed globally in $HOOKS_DIR"
        echo ""
        echo "To apply hooks to existing repos, run in each repo:"
        echo "  git init"
        echo ""
        echo "Or use: git-branch-sync install-repo"
    else
        echo "✓ Hooks installed in current repository: $HOOKS_DIR"
    fi
}

# ============================================================================
# Install hooks in current repo
# ============================================================================
install_repo() {
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        echo "Error: Not in a Git repository"
        exit 1
    fi

    GIT_DIR=$(git rev-parse --git-dir)
    HOOKS_DIR="$GIT_DIR/hooks"
    
    install_hooks "$HOOKS_DIR" false
}

# ============================================================================
# Sync workspace files (for use with cloud sync)
# ============================================================================
sync_info() {
    echo "To sync workspaces across machines, sync this folder:"
    echo "  $SYNC_DIR"
    echo ""
    echo "You can use:"
    echo "  - Dotfiles repo: Add ~/.git-workspaces to your dotfiles"
    echo "  - Cloud sync: Dropbox, Google Drive, iCloud, etc."
    echo "  - rsync: rsync -av ~/.git-workspaces/ other-machine:~/.git-workspaces/"
    echo "  - Git repo: cd ~/.git-workspaces && git init && git add . && git commit"
}

# ============================================================================
# Main command dispatcher
# ============================================================================
case "${1:-}" in
    save)
        save_workspace
        ;;
    restore)
        restore_workspace
        ;;
    list)
        list_workspaces
        ;;
    repo-id)
        show_repo_id
        ;;
    install)
        install_hooks
        ;;
    install-repo)
        install_repo
        ;;
    sync-info)
        sync_info
        ;;
    *)
        echo "Git Branch Sync - Track and restore Git branches across machines"
        echo ""
        echo "Usage: git-branch-sync <command>"
        echo ""
        echo "Commands:"
        echo "  install       Install Git hooks globally (run once per machine)"
        echo "  install-repo  Install hooks in current repository"
        echo "  save          Manually save workspace snapshot for current repo"
        echo "  restore       Restore branches from workspace file"
        echo "  list          List all tracked workspaces"
        echo "  repo-id       Show repository ID for current repo"
        echo "  sync-info     Show how to sync workspaces across machines"
        echo ""
        echo "Workspace files are stored in: $SYNC_DIR"
        ;;
esac