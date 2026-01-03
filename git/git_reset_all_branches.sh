#!/usr/bin/env bash

# Reset All Local Branches
# Resets all local branches to match their remote origin counterparts
# Prompts for confirmation if there are uncommitted changes or local commits ahead
#
# Usage:
#   git_reset_all_branches.sh           - Reset all branches to origin
#   DRY_RUN=true git_reset_all_branches.sh  - Preview what would be reset

# ====================================
# CONFIGURATION
# ====================================

DRY_RUN="${DRY_RUN:-false}"  # Set to true for dry-run mode
EXCLUDED_BRANCHES=("backup/" "temp/" "archive/")  # Add patterns to exclude

# Arrays to track results
SKIPPED_BRANCHES=()
RESET_BRANCHES=()
FAILED_BRANCHES=()
USER_DECLINED_BRANCHES=()

# Git hooks to temporarily deactivate during operations
HOOKS_TO_DEACTIVATE=("post-checkout" "post-merge" "pre-commit")
DEACTIVATED_HOOKS=()

# ====================================
# UTILITY FUNCTIONS
# ====================================

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_dry_run() {
    echo -e "${MAGENTA}[DRY-RUN]${NC} $1"
}

# Check if a branch should be excluded based on patterns
should_exclude_branch() {
    local branch="$1"
    for pattern in "${EXCLUDED_BRANCHES[@]}"; do
        if [[ "$branch" == $pattern* ]]; then
            return 0
        fi
    done
    return 1
}

# Deactivate git hooks by renaming them
deactivate_git_hooks() {
    local git_hooks_dir=".git/hooks"
    
    if [ ! -d "$git_hooks_dir" ]; then
        return 0
    fi
    
    print_status "Deactivating git hooks..."
    
    for hook in "${HOOKS_TO_DEACTIVATE[@]}"; do
        local hook_path="$git_hooks_dir/$hook"
        local disabled_path="$git_hooks_dir/$hook.disabled"
        
        if [ -f "$hook_path" ] && [ ! -f "$disabled_path" ]; then
            if [ "$DRY_RUN" = true ]; then
                print_dry_run "Would deactivate hook: $hook"
            else
                if mv "$hook_path" "$disabled_path" 2>/dev/null; then
                    DEACTIVATED_HOOKS+=("$hook")
                    print_status "Deactivated hook: $hook"
                else
                    print_warning "Failed to deactivate hook: $hook"
                fi
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
    
    print_status "Reactivating git hooks..."
    
    for hook in "${DEACTIVATED_HOOKS[@]}"; do
        local hook_path="$git_hooks_dir/$hook"
        local disabled_path="$git_hooks_dir/$hook.disabled"
        
        if [ -f "$disabled_path" ]; then
            if [ "$DRY_RUN" = true ]; then
                print_dry_run "Would reactivate hook: $hook"
            else
                if mv "$disabled_path" "$hook_path" 2>/dev/null; then
                    print_status "Reactivated hook: $hook"
                else
                    print_error "Failed to reactivate hook: $hook"
                fi
            fi
        fi
    done
    
    DEACTIVATED_HOOKS=()
}

# Cleanup function to ensure hooks are reactivated on exit
cleanup_on_exit() {
    reactivate_git_hooks
}

# Check if branch is ahead of origin
is_ahead_of_origin() {
    local branch="$1"
    local ahead
    ahead=$(git rev-list "origin/$branch..$branch" --count 2>/dev/null)
    if [ -n "$ahead" ] && [ "$ahead" -gt 0 ]; then
        return 0
    fi
    return 1
}

# Get branch status relative to origin (ahead/behind)
# Returns a formatted string like "(2 ahead, 3 behind)", "(up-to-date)", or empty string
get_branch_status() {
    local branch="$1"
    local ahead behind status_parts=()
    
    ahead=$(git rev-list "origin/$branch..$branch" --count 2>/dev/null)
    behind=$(git rev-list "$branch..origin/$branch" --count 2>/dev/null)
    
    if [ -n "$ahead" ] && [ "$ahead" -gt 0 ]; then
        status_parts+=("$ahead ahead")
    fi
    
    if [ -n "$behind" ] && [ "$behind" -gt 0 ]; then
        status_parts+=("$behind behind")
    fi
    
    if [ ${#status_parts[@]} -gt 0 ]; then
        # Join array elements with ", "
        local status=""
        for i in "${!status_parts[@]}"; do
            if [ $i -gt 0 ]; then
                status="$status, "
            fi
            status="$status${status_parts[$i]}"
        done
        echo "($status)"
    else
        echo "(up-to-date)"
    fi
}

# Prompt user for confirmation
# Returns 0 if user confirms (y), 1 otherwise (N is default)
prompt_user() {
    local message="$1"
    local response
    
    echo -e "${YELLOW}$message${NC}"
    read -p "Continue? [y/N]: " -r response < /dev/tty
    
    if [[ "$response" =~ ^[Yy]$ ]]; then
        return 0
    else
        return 1
    fi
}

# Process a single branch for reset
# Args: branch_name, is_current_branch (true/false)
process_branch_reset() {
    local branch="$1"
    local is_current="$2"
    
    # Skip excluded branches
    if should_exclude_branch "$branch"; then
        print_warning "Skipping excluded branch: $branch"
        SKIPPED_BRANCHES+=("$branch")
        return
    fi
    
    # Check if remote branch exists
    if ! git show-ref --verify --quiet "refs/remotes/origin/$branch"; then
        print_warning "Branch '$branch' has no remote counterpart, skipping"
        SKIPPED_BRANCHES+=("$branch")
        return
    fi
    
    # Get branch status relative to origin
    local branch_status
    branch_status=$(get_branch_status "$branch")
    
    print_status "Processing branch: $branch $branch_status"
    
    # Skip if branch is up-to-date
    if [[ "$branch_status" == "(up-to-date)" ]]; then
        print_success "Branch '$branch' is up-to-date, skipping reset"
        SKIPPED_BRANCHES+=("$branch")
        echo ""
        return
    fi
    
    # Switch to branch only if not current
    if [ "$is_current" = false ] && [ "$DRY_RUN" = false ]; then
        git checkout "$branch" --quiet 2>/dev/null
        if [ $? -ne 0 ]; then
            print_error "Failed to checkout branch: $branch"
            FAILED_BRANCHES+=("$branch")
            return
        fi
    fi
    
    # Check for uncommitted changes
    needs_confirmation=false
    confirmation_reason=""
    
    if [ "$DRY_RUN" = false ]; then
        if [[ -n $(git status --porcelain) ]]; then
            needs_confirmation=true
            confirmation_reason="uncommitted changes"
            print_warning "Branch '$branch' has uncommitted changes"
        fi
        
        # Check if branch is ahead of origin
        if is_ahead_of_origin "$branch"; then
            needs_confirmation=true
            if [ -n "$confirmation_reason" ]; then
                confirmation_reason="$confirmation_reason and local commits ahead of origin"
            else
                confirmation_reason="local commits ahead of origin"
            fi
            
            local ahead_count
            ahead_count=$(git rev-list "origin/$branch..$branch" --count)
            print_warning "Branch '$branch' is $ahead_count commit(s) ahead of origin"
        fi
    fi
    
    # Prompt if needed
    if [ "$needs_confirmation" = true ]; then
        echo ""
        if ! prompt_user "Branch '$branch' has $confirmation_reason. Reset will discard these changes."; then
            print_status "Skipping branch: $branch (not confirmed)"
            USER_DECLINED_BRANCHES+=("$branch")
            echo ""
            return
        fi
        echo ""
    fi
    
    # Reset branch to origin
    if [ "$DRY_RUN" = true ]; then
        print_dry_run "Would reset branch '$branch' to origin/$branch"
        RESET_BRANCHES+=("$branch")
    else
        if git reset --hard "origin/$branch" --quiet 2>/dev/null; then
            print_success "Reset branch '$branch' to origin/$branch"
            RESET_BRANCHES+=("$branch")
        else
            print_error "Failed to reset branch: $branch"
            FAILED_BRANCHES+=("$branch")
        fi
    fi
    
    echo ""
}

# ====================================
# MAIN LOGIC
# ====================================

# Set up trap to ensure cleanup
trap cleanup_on_exit EXIT

# Verify we're in a git repository
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null)
if [ -z "$REPO_ROOT" ]; then
    print_error "Not in a Git repository"
    exit 1
fi

print_status "Starting branch reset process..."
print_status "Repository: $REPO_ROOT"
echo ""

# Store current branch to return to it later
ORIGINAL_BRANCH=$(git branch --show-current)

# Fetch latest from all remotes
print_status "Fetching from all remotes..."
if [ "$DRY_RUN" = true ]; then
    print_dry_run "Would fetch from all remotes"
else
    if ! git fetch --all --quiet; then
        print_error "Failed to fetch from remotes"
        exit 1
    fi
fi

# Deactivate git hooks
deactivate_git_hooks

# Get all local branches
ALL_BRANCHES=$(git branch --format='%(refname:short)')

print_status "Processing branches..."
echo ""

# Process current branch first (to handle cases where repo is in weird state)
if [ -n "$ORIGINAL_BRANCH" ]; then
    print_status "Processing current branch first: $ORIGINAL_BRANCH"
    process_branch_reset "$ORIGINAL_BRANCH" true
fi

# Process all other branches
while IFS= read -r branch; do
    # Skip if it's the current branch (already processed)
    if [ "$branch" = "$ORIGINAL_BRANCH" ]; then
        continue
    fi
    
    process_branch_reset "$branch" false
done <<< "$ALL_BRANCHES"

# Return to original branch if it still exists and wasn't the one we're on
if [ "$DRY_RUN" = false ] && [ -n "$ORIGINAL_BRANCH" ]; then
    CURRENT=$(git branch --show-current)
    if [ "$CURRENT" != "$ORIGINAL_BRANCH" ]; then
        print_status "Returning to original branch: $ORIGINAL_BRANCH"
        git checkout "$ORIGINAL_BRANCH" --quiet 2>/dev/null
    fi
fi

# Print summary
echo ""
print_status "======================================"
print_status "SUMMARY"
print_status "======================================"

if [ ${#RESET_BRANCHES[@]} -gt 0 ]; then
    if [ "$DRY_RUN" = true ]; then
        print_dry_run "Branches that would be reset: ${#RESET_BRANCHES[@]}"
    else
        print_success "Branches successfully reset: ${#RESET_BRANCHES[@]}"
    fi
    for branch in "${RESET_BRANCHES[@]}"; do
        echo "  - $branch"
    done
    echo ""
fi

if [ ${#USER_DECLINED_BRANCHES[@]} -gt 0 ]; then
    print_warning "Branches not confirmed (skipped): ${#USER_DECLINED_BRANCHES[@]}"
    for branch in "${USER_DECLINED_BRANCHES[@]}"; do
        echo "  - $branch"
    done
    echo ""
fi

if [ ${#SKIPPED_BRANCHES[@]} -gt 0 ]; then
    print_warning "Branches skipped: ${#SKIPPED_BRANCHES[@]}"
    for branch in "${SKIPPED_BRANCHES[@]}"; do
        echo "  - $branch"
    done
    echo ""
fi

if [ ${#FAILED_BRANCHES[@]} -gt 0 ]; then
    print_error "Branches failed: ${#FAILED_BRANCHES[@]}"
    for branch in "${FAILED_BRANCHES[@]}"; do
        echo "  - $branch"
    done
    echo ""
fi

# Exit with appropriate code
if [ ${#FAILED_BRANCHES[@]} -gt 0 ]; then
    exit 2
else
    exit 0
fi
