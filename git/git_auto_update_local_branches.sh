#!/bin/bash

set -e  # Exit on any error

# ====================================
# CONFIGURATION
# ====================================

MAIN_BRANCH="${1:-main}"  # First argument or default to 'main'
EXCLUDED_BRANCHES=("backup/" "temp/" "archive/")  # Add patterns to exclude
EXCLUDED_GH_LABELS=("mergequeue")  # Add GitHub labels to exclude branches with these labels
DRY_RUN="${DRY_RUN:-false}"  # Set to true for dry-run mode
NO_PUSH="${NO_PUSH:-false}"  # Set to true to prevent pushing to remote

# Arrays to track results
IGNORED_BRANCHES=()
SUCCESSFUL_BRANCHES=()
FAILED_BRANCHES=()
MERGE_CONFLICT_BRANCHES=()
REBASE_CONFLICT_BRANCHES=()
REBASED_BRANCHES=()

# Cache for tool availability
GH_AVAILABLE=false
NPM_AVAILABLE=false

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

# Function to print colored output
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

# Verify working directory is clean
verify_clean_working_directory() {
    if [[ -n $(git status --porcelain) ]]; then
        return 1
    fi
    return 0
}

# ====================================
# BRANCH IDENTIFICATION FUNCTIONS
# ====================================

# Check if a branch is a stacked branch
# Stacked branches follow the pattern: stacked/parent-ticket/branch-name
is_stacked_branch() {
    local branch="$1"
    [[ "$branch" =~ ^stacked/ ]]
}

# Extract the parent ticket number from a stacked branch name
# Example: stacked/br1234/BR-2345-my-feature -> br1234
# Returns empty string if branch doesn't follow the correct pattern
extract_parent_ticket() {
    local branch="$1"
    if [[ "$branch" =~ ^stacked/([^/]+)/(.+)$ ]]; then
        echo "${BASH_REMATCH[1]}"
    else
        return 1
    fi
}

# Normalize a ticket identifier by removing special characters and converting to lowercase
# Example: BR-1234 -> br1234
normalize_ticket() {
    local ticket="$1"
    echo "$ticket" | tr -d '\-_' | tr '[:upper:]' '[:lower:]'
}

# Extract ticket number from a branch name (assumes ticket is at the start)
# Example: BR-1234-my-feature -> br1234
extract_ticket_from_branch() {
    local branch="$1"
    # Try to extract ticket pattern (letters followed by optional dash/underscore and numbers)
    if [[ "$branch" =~ ^([A-Za-z]+[-_]?[0-9]+) ]]; then
        normalize_ticket "${BASH_REMATCH[1]}"
    fi
}

# Find the parent branch for a stacked branch
# Returns the full branch name if found, empty string otherwise
# Preference order: non-stacked branches, then oldest stacked branch
find_parent_branch() {
    local stacked_branch="$1"
    local parent_ticket
    parent_ticket=$(extract_parent_ticket "$stacked_branch")
    
    if [ -z "$parent_ticket" ]; then
        return 1
    fi
    
    # Normalize the parent ticket
    local normalized_parent
    normalized_parent=$(normalize_ticket "$parent_ticket")
    
    # Search through all branches to find the matching parent
    local all_branches
    all_branches=$(git branch --format='%(refname:short)')
    
    local found_branches=()
    
    while IFS= read -r branch; do
        # Skip the stacked branch itself
        if [ "$branch" = "$stacked_branch" ]; then
            continue
        fi
        
        # Extract and normalize ticket from this branch
        local branch_ticket
        branch_ticket=$(extract_ticket_from_branch "$branch")
        
        if [ -n "$branch_ticket" ] && [ "$branch_ticket" = "$normalized_parent" ]; then
            found_branches+=("$branch")
        fi
    done <<< "$all_branches"
    
    # If no matches found, return error
    if [ ${#found_branches[@]} -eq 0 ]; then
        return 1
    fi
    
    # If multiple matches, prefer non-stacked branches
    for branch in "${found_branches[@]}"; do
        if ! is_stacked_branch "$branch"; then
            echo "$branch"
            return 0
        fi
    done
    
    # If only stacked branches found, warn and return first one
    if [ ${#found_branches[@]} -gt 1 ]; then
        print_warning "Multiple parent candidates found for $stacked_branch: ${found_branches[*]}"
        print_warning "Using first match: ${found_branches[0]}"
    fi
    
    echo "${found_branches[0]}"
    return 0
}

# Check if a branch has been merged into main
is_merged_to_main() {
    local branch="$1"
    git merge-base --is-ancestor "$branch" "$MAIN_BRANCH" 2>/dev/null && \
    ! git merge-base --is-ancestor "$MAIN_BRANCH" "$branch" 2>/dev/null
}

# Check if remote branch exists
remote_branch_exists() {
    local branch="$1"
    git ls-remote --exit-code --heads origin "$branch" >/dev/null 2>&1
}

# ====================================
# BRANCH EXCLUSION FUNCTIONS
# ====================================

# Function to check if branch should be excluded
should_exclude_branch() {
    local branch="$1"
    
    # Skip the main branch
    if [ "$branch" = "$MAIN_BRANCH" ]; then
        return 0  # exclude
    fi
    
    # Check against excluded patterns
    for pattern in "${EXCLUDED_BRANCHES[@]}"; do
        if [[ "$branch" == *"$pattern"* ]]; then
            return 0  # exclude
        fi
    done
    
    # Check for excluded GitHub labels (only if GH is available)
    if [ "$GH_AVAILABLE" = true ]; then
        pr_info=$(gh pr list --head "$branch" --json number,labels --jq '.[0]' 2>/dev/null)
        if [ -n "$pr_info" ] && [ "$pr_info" != "null" ]; then
            labels=$(echo "$pr_info" | jq -r '.labels[].name' 2>/dev/null)
            for label in $labels; do
                for excluded_label in "${EXCLUDED_GH_LABELS[@]}"; do
                    if [ "$label" = "$excluded_label" ]; then
                        return 0  # exclude
                    fi
                done
            done
        fi
    fi
    
    return 1  # don't exclude
}

# ====================================
# TOPOLOGICAL SORT FOR STACKED BRANCHES
# ====================================

# Build dependency map for stacked branches
# Returns array of branches in correct processing order
topological_sort_stacked_branches() {
    # Read branches from arguments
    local branches=("$@")
    local sorted=()
    local visited=()
    local in_progress=()
    
    # Helper function for depth-first search
    visit_branch() {
        local branch="$1"
        
        # Check if already visited
        for v in "${visited[@]}"; do
            if [ "$v" = "$branch" ]; then
                return 0
            fi
        done
        
        # Check for circular dependency
        for ip in "${in_progress[@]}"; do
            if [ "$ip" = "$branch" ]; then
                print_warning "Circular dependency detected involving $branch"
                return 1
            fi
        done
        
        in_progress+=("$branch")
        
        # If this is a stacked branch, visit its parent first
        if is_stacked_branch "$branch"; then
            local parent
            parent=$(find_parent_branch "$branch" 2>/dev/null) || true
            
            if [ -n "$parent" ]; then
                # Check if parent is in our list of stacked branches
                for sb in "${branches[@]}"; do
                    if [ "$sb" = "$parent" ]; then
                        visit_branch "$parent"
                        break
                    fi
                done
            fi
        fi
        
        # Remove from in_progress
        local temp=()
        for ip in "${in_progress[@]}"; do
            if [ "$ip" != "$branch" ]; then
                temp+=("$ip")
            fi
        done
        in_progress=("${temp[@]}")
        
        # Add to visited and sorted
        visited+=("$branch")
        sorted+=("$branch")
    }
    
    # Visit all branches
    for branch in "${branches[@]}"; do
        visit_branch "$branch"
    done
    
    # Return sorted array
    echo "${sorted[@]}"
}

# ====================================
# BRANCH PROCESSING FUNCTIONS
# ====================================

# Merge main into a branch (helper function for both regular and stacked branches)
merge_main_into_branch() {
    local branch="$1"
    
    # Check for uncommitted changes before switching branches
    if ! verify_clean_working_directory; then
        print_error "Uncommitted changes detected. Skipping $branch. Please commit or stash changes first."
        FAILED_BRANCHES+=("$branch")
        return 1
    fi

    # Checkout the branch
    if ! git checkout "$branch" 2>/dev/null; then
        print_error "Failed to checkout $branch"
        FAILED_BRANCHES+=("$branch")
        return 1
    fi

    # Check for uncommitted changes after checkout
    if ! verify_clean_working_directory; then
        print_error "Uncommitted changes detected in $branch. Skipping. Please commit or stash changes first."
        FAILED_BRANCHES+=("$branch")
        return 1
    fi

    # Pull latest changes for this branch
    if remote_branch_exists "$branch"; then
        print_status "Pulling latest changes for $branch..."
        if [ "$DRY_RUN" = true ]; then
            print_dry_run "Would pull origin/$branch"
        else
            if ! git pull origin "$branch"; then
                print_error "Failed to pull $branch. There may be conflicts or connectivity issues."
                FAILED_BRANCHES+=("$branch")
                return 1
            fi
        fi
    else
        print_warning "Remote branch origin/$branch not found. Skipping pull."
    fi

    # Verify still clean after pull
    if ! verify_clean_working_directory; then
        print_error "Working directory not clean after pull in $branch"
        FAILED_BRANCHES+=("$branch")
        return 1
    fi

    # Check if the branch is already up-to-date with MAIN_BRANCH
    if git merge-base --is-ancestor "$MAIN_BRANCH" "$branch" 2>/dev/null; then
        print_warning "Branch $branch is already up-to-date with $MAIN_BRANCH. Skipping merge."
        SUCCESSFUL_BRANCHES+=("$branch")
        return 0
    fi

    # Attempt to merge main
    print_status "Merging $MAIN_BRANCH into $branch..."

    if [ "$DRY_RUN" = true ]; then
        print_dry_run "Would merge $MAIN_BRANCH into $branch"
        # Check if merge would conflict
        if git merge-tree "$(git merge-base "$MAIN_BRANCH" "$branch")" "$MAIN_BRANCH" "$branch" | grep -q "^changed in both"; then
            print_warning "Merge would have conflicts"
            MERGE_CONFLICT_BRANCHES+=("$branch")
            return 1
        else
            print_success "Merge would succeed for $branch"
            SUCCESSFUL_BRANCHES+=("$branch")
            return 0
        fi
    fi

    if git merge "$MAIN_BRANCH" --no-edit; then
        print_success "Merge successful for $branch"

        # Verify working directory is still clean
        if ! verify_clean_working_directory; then
            print_error "Working directory not clean after merge in $branch"
            FAILED_BRANCHES+=("$branch")
            return 1
        fi

        # Push the changes
        print_status "Pushing $branch..."
        if [ "$NO_PUSH" = true ]; then
            print_warning "Skipping push (NO_PUSH mode enabled)"
            SUCCESSFUL_BRANCHES+=("$branch")
            return 0
        elif git push origin "$branch"; then
            print_success "Successfully pushed $branch"
            SUCCESSFUL_BRANCHES+=("$branch")
            return 0
        else
            print_error "Failed to push $branch"
            FAILED_BRANCHES+=("$branch")
            return 1
        fi
    else
        print_warning "Merge conflict detected in $branch"

        # Abort the merge
        git merge --abort
        
        # Verify abort was successful
        if ! verify_clean_working_directory; then
            print_error "Working directory not clean after merge abort in $branch"
            FAILED_BRANCHES+=("$branch")
            return 1
        fi
        
        print_status "Merge aborted for $branch"
        MERGE_CONFLICT_BRANCHES+=("$branch")
        return 1
    fi
}

# Process a regular (non-stacked) branch by merging main into it
process_regular_branch() {
    local branch="$1"
    
    print_status "Processing regular branch: $branch"
    merge_main_into_branch "$branch"
}

# Process a stacked branch by rebasing on parent or merging main
process_stacked_branch() {
    local branch="$1"
    
    print_status "Processing stacked branch: $branch"
    
    # Validate branch name format
    local parent_ticket
    parent_ticket=$(extract_parent_ticket "$branch" 2>/dev/null) || true
    
    if [ -z "$parent_ticket" ]; then
        print_error "Invalid stacked branch format: $branch"
        print_error "Expected format: stacked/parent-ticket/branch-name"
        FAILED_BRANCHES+=("$branch")
        return 0  # Return 0 to not trigger set -e
    fi
    
    # Find the parent branch
    local parent_branch
    parent_branch=$(find_parent_branch "$branch" 2>/dev/null) || true
    
    if [ -z "$parent_branch" ]; then
        print_warning "Could not find parent branch for $branch (looking for ticket: $parent_ticket)"
        print_warning "Parent branch may have been merged or deleted. Will merge from $MAIN_BRANCH instead."
        merge_main_into_branch "$branch"
        return 0
    fi
    
    print_status "Parent branch for $branch: $parent_branch"
    
    # Check for uncommitted changes before switching branches
    if ! verify_clean_working_directory; then
        print_error "Uncommitted changes detected. Skipping $branch. Please commit or stash changes first."
        FAILED_BRANCHES+=("$branch")
        return 1
    fi

    # Checkout the stacked branch
    if ! git checkout "$branch" 2>/dev/null; then
        print_error "Failed to checkout $branch"
        FAILED_BRANCHES+=("$branch")
        return 1
    fi

    # Check for uncommitted changes after checkout
    if ! verify_clean_working_directory; then
        print_error "Uncommitted changes detected in $branch. Skipping. Please commit or stash changes first."
        FAILED_BRANCHES+=("$branch")
        return 1
    fi

    # Pull latest changes for this branch
    if remote_branch_exists "$branch"; then
        print_status "Pulling latest changes for $branch..."
        if [ "$DRY_RUN" = true ]; then
            print_dry_run "Would pull origin/$branch"
        else
            if ! git pull origin "$branch"; then
                print_error "Failed to pull $branch. There may be conflicts or connectivity issues."
                FAILED_BRANCHES+=("$branch")
                return 1
            fi
        fi
    else
        print_warning "Remote branch origin/$branch not found. Skipping pull."
    fi

    # Verify still clean after pull
    if ! verify_clean_working_directory; then
        print_error "Working directory not clean after pull in $branch"
        FAILED_BRANCHES+=("$branch")
        return 1
    fi
    
    # Check if parent branch has been merged to main
    if is_merged_to_main "$parent_branch"; then
        print_status "Parent branch $parent_branch has been merged to $MAIN_BRANCH"
        print_status "Merging $MAIN_BRANCH into $branch instead of rebasing..."
        merge_main_into_branch "$branch"
        return 0
    else
        print_status "Rebasing $branch onto $parent_branch..."
        
        if [ "$DRY_RUN" = true ]; then
            print_dry_run "Would rebase $branch onto $parent_branch"
            print_warning "Branch would need manual force-push after rebase"
            REBASED_BRANCHES+=("$branch")
            return 0
        fi
        
        if git rebase "$parent_branch"; then
            print_success "Rebase successful for $branch"
            
            # Verify working directory is clean
            if ! verify_clean_working_directory; then
                print_error "Working directory not clean after rebase in $branch"
                FAILED_BRANCHES+=("$branch")
                return 1
            fi
            
            print_warning "Branch $branch has been rebased locally but NOT pushed."
            if [ "$NO_PUSH" = true ]; then
                print_warning "To push when ready: git push --force-with-lease origin $branch"
            else
                print_warning "To push: git push --force-with-lease origin $branch"
            fi
            REBASED_BRANCHES+=("$branch")
            return 0
        else
            print_warning "Rebase conflict detected in $branch"
            git rebase --abort
            
            # Verify abort was successful
            if ! verify_clean_working_directory; then
                print_error "Working directory not clean after rebase abort in $branch"
                FAILED_BRANCHES+=("$branch")
                return 1
            fi
            
            print_status "Rebase aborted for $branch"
            REBASE_CONFLICT_BRANCHES+=("$branch")
            return 1
        fi
    fi
}

# ====================================
# INITIALIZATION AND CHECKS
# ====================================

# Check if we're in a git repository
if ! git rev-parse --git-dir > /dev/null 2>&1; then
    print_error "Not in a git repository!"
    exit 1
fi

# Check and cache GitHub CLI availability
if command -v gh >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
    if gh auth status >/dev/null 2>&1; then
        GH_AVAILABLE=true
        print_status "GitHub CLI is available and authenticated"
    else
        print_warning "GitHub CLI (gh) is installed but not authenticated. GitHub label checks will be skipped."
    fi
else
    if ! command -v gh >/dev/null 2>&1; then
        print_warning "GitHub CLI (gh) is not installed. GitHub label checks will be skipped."
    fi
    if ! command -v jq >/dev/null 2>&1; then
        print_warning "jq is not installed. GitHub label checks will be skipped."
    fi
fi

# Check npm availability
if command -v npm >/dev/null 2>&1; then
    NPM_AVAILABLE=true
else
    print_warning "npm is not installed. npm install will be skipped."
fi

# Store the current branch
ORIGINAL_BRANCH=$(git branch --show-current)

if [ "$DRY_RUN" = true ]; then
    print_dry_run "DRY-RUN MODE: No changes will be made"
fi

if [ "$NO_PUSH" = true ]; then
    print_warning "NO_PUSH MODE: Changes will be made locally but not pushed to remote"
fi

print_status "Main branch: $MAIN_BRANCH"
print_status "Currently on branch: $ORIGINAL_BRANCH"
print_status "Excluded patterns: ${EXCLUDED_BRANCHES[*]}"
print_status "Excluded GitHub labels: ${EXCLUDED_GH_LABELS[*]}"

# Fetch latest changes
print_status "Fetching latest changes..."
if [ "$DRY_RUN" = true ]; then
    print_dry_run "Would fetch from origin"
else
    git fetch origin
fi

# Update main branch
print_status "Updating $MAIN_BRANCH branch..."
if [ "$DRY_RUN" = true ]; then
    print_dry_run "Would checkout and pull $MAIN_BRANCH"
else
    git checkout "$MAIN_BRANCH"
    git pull origin "$MAIN_BRANCH"
fi

# ====================================
# BRANCH COLLECTION AND CATEGORIZATION
# ====================================

# Get all local branches and categorize them
ALL_BRANCHES=$(git branch --format='%(refname:short)')
REGULAR_BRANCHES=()
STACKED_BRANCHES=()

while IFS= read -r branch; do
    if should_exclude_branch "$branch"; then
        IGNORED_BRANCHES+=("$branch")
        continue
    fi
    
    if is_stacked_branch "$branch"; then
        STACKED_BRANCHES+=("$branch")
    else
        REGULAR_BRANCHES+=("$branch")
    fi
done <<< "$ALL_BRANCHES"

if [ ${#REGULAR_BRANCHES[@]} -eq 0 ] && [ ${#STACKED_BRANCHES[@]} -eq 0 ]; then
    print_warning "No branches found to update (after applying exclusions)"
    if [ "$DRY_RUN" = false ]; then
        git checkout "$ORIGINAL_BRANCH"
    fi
    exit 0
fi

print_status "Found regular branches to update (${#REGULAR_BRANCHES[@]}):"
if [ ${#REGULAR_BRANCHES[@]} -gt 0 ]; then
    printf '%s\n' "${REGULAR_BRANCHES[@]}" | sed 's/^/  - /'
else
    echo "  (none)"
fi

print_status "Found stacked branches to update (${#STACKED_BRANCHES[@]}):"
if [ ${#STACKED_BRANCHES[@]} -gt 0 ]; then
    printf '%s\n' "${STACKED_BRANCHES[@]}" | sed 's/^/  - /'
else
    echo "  (none)"
fi

echo

# ====================================
# PHASE 1: PROCESS REGULAR BRANCHES
# ====================================

print_status "=== PHASE 1: Processing regular branches ==="
echo

for branch in "${REGULAR_BRANCHES[@]}"; do
    process_regular_branch "$branch"
    echo  # Empty line for readability
done

# ====================================
# PHASE 2: PROCESS STACKED BRANCHES
# ====================================

if [ ${#STACKED_BRANCHES[@]} -gt 0 ]; then
    print_status "=== PHASE 2: Processing stacked branches ==="
    echo
    
    # Sort stacked branches topologically
    print_status "Sorting stacked branches by dependencies..."
    SORTED_STACKED_BRANCHES=($(topological_sort_stacked_branches "${STACKED_BRANCHES[@]}"))
    
    print_status "Processing order:"
    printf '%s\n' "${SORTED_STACKED_BRANCHES[@]}" | sed 's/^/  - /'
    echo
    
    for branch in "${SORTED_STACKED_BRANCHES[@]}"; do
        process_stacked_branch "$branch"
        echo  # Empty line for readability
    done
fi

# ====================================
# CLEANUP AND SUMMARY
# ====================================

# Return to original branch
print_status "Returning to original branch: $ORIGINAL_BRANCH"
if [ "$DRY_RUN" = false ]; then
    git checkout "$ORIGINAL_BRANCH"
fi

# Run npm install if npm is available and package.json exists
if [ "$NPM_AVAILABLE" = true ] && [ -f "package.json" ] && [ "$DRY_RUN" = false ]; then
    # Check if package-lock.json or node_modules changed
    if git diff --name-only "$ORIGINAL_BRANCH@{1}" "$ORIGINAL_BRANCH" | grep -qE 'package-lock.json|package.json'; then
        print_status "Dependencies may have changed. Running npm install..."
        if npm install; then
            print_success "npm install successful"
        else
            print_error "npm install failed"
            exit 1
        fi
    else
        print_status "No dependency changes detected. Skipping npm install."
    fi
fi

# Print summary
echo
print_status "=== SUMMARY ==="

if [ ${#IGNORED_BRANCHES[@]} -gt 0 ]; then
    print_warning "Ignored branches (${#IGNORED_BRANCHES[@]}):"
    printf '%s\n' "${IGNORED_BRANCHES[@]}" | sed 's/^/  ⊝ /'
fi

if [ ${#SUCCESSFUL_BRANCHES[@]} -gt 0 ]; then
    print_success "Updated branches (${#SUCCESSFUL_BRANCHES[@]}):"
    printf '%s\n' "${SUCCESSFUL_BRANCHES[@]}" | sed 's/^/  ✓ /'
fi

if [ ${#REBASED_BRANCHES[@]} -gt 0 ]; then
    print_success "Rebased stacked branches (requires manual force-push) (${#REBASED_BRANCHES[@]}):"
    printf '%s\n' "${REBASED_BRANCHES[@]}" | sed 's/^/  ↻ /'
    echo -e "${YELLOW}⚠ These branches need to be force-pushed manually:${NC}"
    for branch in "${REBASED_BRANCHES[@]}"; do
        echo -e "  ${YELLOW}git push --force-with-lease origin $branch${NC}"
    done
fi

if [ ${#MERGE_CONFLICT_BRANCHES[@]} -gt 0 ]; then
    print_warning "Branches with merge conflicts (${#MERGE_CONFLICT_BRANCHES[@]}):"
    printf '%s\n' "${MERGE_CONFLICT_BRANCHES[@]}" | sed 's/^/  ⚠ /'
    echo -e "${YELLOW}These branches need manual conflict resolution${NC}"
fi

if [ ${#REBASE_CONFLICT_BRANCHES[@]} -gt 0 ]; then
    print_warning "Branches with rebase conflicts (${#REBASE_CONFLICT_BRANCHES[@]}):"
    printf '%s\n' "${REBASE_CONFLICT_BRANCHES[@]}" | sed 's/^/  ⚠ /'
    echo -e "${YELLOW}These branches need manual conflict resolution${NC}"
fi

if [ ${#FAILED_BRANCHES[@]} -gt 0 ]; then
    print_error "Branches that failed (${#FAILED_BRANCHES[@]}):"
    printf '%s\n' "${FAILED_BRANCHES[@]}" | sed 's/^/  ✗ /'
fi

echo
if [ "$DRY_RUN" = true ]; then
    print_dry_run "Dry-run completed! No actual changes were made."
elif [ "$NO_PUSH" = true ]; then
    print_warning "Operation completed! Changes made locally but not pushed to remote."
else
    print_status "Operation completed!"
fi

# Exit with appropriate code
if [ ${#FAILED_BRANCHES[@]} -gt 0 ]; then
    exit 1
elif [ ${#MERGE_CONFLICT_BRANCHES[@]} -gt 0 ] || [ ${#REBASE_CONFLICT_BRANCHES[@]} -gt 0 ]; then
    exit 10  # More distinctive exit code for conflicts
else
    exit 0
fi