#!/bin/bash
# Git Branch Sync System
# Automatically tracks and syncs your Git branches across machines

SYNC_DIR="$HOME/.git-workspaces"
SCRIPT_ZSH_ALIAS="git-branch-sync"

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
# Core update function - called by Git hooks
# ============================================================================
update_workspace() {
    REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null)
    if [ -z "$REPO_ROOT" ]; then
        exit 0
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
    BRANCHES=$(git branch --format='%(refname:short)')
    REMOTE_URL=$(git config --get remote.origin.url 2>/dev/null)

    cat > "$WORKSPACE_FILE" <<EOF
repo_path=$REPO_ROOT
remote_url=$REMOTE_URL
current_branch=$CURRENT
updated=$(date -u +"%Y-%m-%d %H:%M:%S UTC")

# Branches (one per line)
EOF

    echo "$BRANCHES" >> "$WORKSPACE_FILE"
    
    echo "✓ Workspace updated: $WORKSPACE_FILE"
}

# ============================================================================
# Restore workspace for current repo
# ============================================================================
restore_workspace() {
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
    
    # Fetch from all remotes
    echo "Fetching from remotes..."
    git fetch --all --quiet

    # Restore each branch
    for branch in "${BRANCHES[@]}"; do
        if git show-ref --verify --quiet "refs/heads/$branch"; then
            echo "  ✓ $branch (already exists)"
        elif git show-ref --verify --quiet "refs/remotes/origin/$branch"; then
            git checkout -b "$branch" "origin/$branch" --quiet 2>/dev/null
            echo "  ✓ $branch (created from origin)"
        else
            echo "  ✗ $branch (not found in remote)"
        fi
    done

    # Checkout the current branch
    if [ -n "$CURRENT_BRANCH" ] && git show-ref --verify --quiet "refs/heads/$CURRENT_BRANCH"; then
        git checkout "$CURRENT_BRANCH" --quiet
        echo ""
        echo "✓ Restored to branch: $CURRENT_BRANCH"
    fi
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
    HOOKS_DIR="$HOME/.git-templates/hooks"
    mkdir -p "$HOOKS_DIR"

    # Create post-checkout hook
    cat > "$HOOKS_DIR/post-checkout" <<HOOK_EOF
#!/bin/bash
# Auto-update workspace on branch checkout
$SCRIPT_ZSH_ALIAS update
HOOK_EOF

    # Create post-commit hook
    cat > "$HOOKS_DIR/post-commit" <<HOOK_EOF
#!/bin/bash
# Auto-update workspace on commit (catches new branches)
$SCRIPT_ZSH_ALIAS update
HOOK_EOF

    chmod +x "$HOOKS_DIR"/*

    # Configure Git to use this template
    git config --global init.templateDir "$HOME/.git-templates"

    echo "✓ Git hooks installed in $HOOKS_DIR"
    echo ""
    echo "To apply hooks to existing repos, run in each repo:"
    echo "  git init"
    echo ""
    echo "Or use: git-branch-sync install-repo"
}

# ============================================================================
# Install hooks in current repo
# ============================================================================
install_repo() {
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        echo "Error: Not in a Git repository"
        exit 1
    fi

    git init
    echo "✓ Hooks installed in current repository"
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
    update)
        update_workspace
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
        echo "  update        Manually update workspace for current repo"
        echo "  restore       Restore branches from workspace file"
        echo "  list          List all tracked workspaces"
        echo "  repo-id       Show repository ID for current repo"
        echo "  sync-info     Show how to sync workspaces across machines"
        echo ""
        echo "Workspace files are stored in: $SYNC_DIR"
        ;;
esac