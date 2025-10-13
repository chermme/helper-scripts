#!/bin/bash

set -e  # Exit on any error

# Configuration
MAIN_BRANCH="${1:-main}"  # First argument or default to 'main'
EXCLUDED_BRANCHES=("backup/" "temp/" "archive/" "stacked/")  # Add patterns to exclude
EXCLUDED_GH_LABELS=("mergequeue")  # Add GitHub labels to exclude branches with these labels

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
    
    # Check for excluded GitHub labels
    if command -v gh >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
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

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

# Check if we're in a git repository
if ! git rev-parse --git-dir > /dev/null 2>&1; then
    print_error "Not in a git repository!"
    exit 1
fi

# Check if gh is installed and authenticated
if command -v gh >/dev/null 2>&1; then
    if ! gh auth status >/dev/null 2>&1; then
        print_warning "GitHub CLI (gh) is installed but not authenticated. GitHub label checks will be skipped."
    fi
else
    print_warning "GitHub CLI (gh) is not installed. GitHub label checks will be skipped."
fi

# Check if jq is installed
if ! command -v jq >/dev/null 2>&1; then
    print_warning "jq is not installed. GitHub label checks will be skipped."
fi

# Check if npm is installed
if ! command -v npm >/dev/null 2>&1; then
    print_warning "npm is not installed. npm install will be skipped."
fi

# Store the current branch
ORIGINAL_BRANCH=$(git branch --show-current)
print_status "Main branch: $MAIN_BRANCH"
print_status "Currently on branch: $ORIGINAL_BRANCH"
print_status "Excluded patterns: ${EXCLUDED_BRANCHES[*]}"
print_status "Excluded GitHub labels: ${EXCLUDED_GH_LABELS[*]}"

# Fetch latest changes
print_status "Fetching latest changes..."
git fetch origin

# Update main branch
print_status "Updating $MAIN_BRANCH branch..."
git checkout "$MAIN_BRANCH"
git pull origin "$MAIN_BRANCH"

# Get all local branches and filter out excluded ones
ALL_BRANCHES=$(git branch --format='%(refname:short)')
BRANCHES=()

while IFS= read -r branch; do
    if should_exclude_branch "$branch"; then
        print_warning "Branch $branch excluded (matches exclusion criteria)"
        continue
    fi
    BRANCHES+=("$branch")
done <<< "$ALL_BRANCHES"

if [ ${#BRANCHES[@]} -eq 0 ]; then
    print_warning "No branches found to update (after applying exclusions)"
    git checkout "$ORIGINAL_BRANCH"
    exit 0
fi

print_status "Found branches to update:"
printf '%s\n' "${BRANCHES[@]}" | sed 's/^/  - /'

# Arrays to track results
SUCCESSFUL_BRANCHES=()
FAILED_BRANCHES=()
CONFLICT_BRANCHES=()

# Process each branch
for BRANCH in "${BRANCHES[@]}"; do
    print_status "Processing branch: $BRANCH"

    # Check for uncommitted changes before switching branches
    if [[ -n $(git status --porcelain) ]]; then
        print_error "Uncommitted changes detected. Skipping $BRANCH. Please commit or stash changes first."
        FAILED_BRANCHES+=("$BRANCH")
        continue
    fi

    # Checkout the branch
    if ! git checkout "$BRANCH" 2>/dev/null; then
        print_error "Failed to checkout $BRANCH"
        FAILED_BRANCHES+=("$BRANCH")
        continue
    fi

    # Check for uncommitted changes after checkout
    if [[ -n $(git status --porcelain) ]]; then
        print_error "Uncommitted changes detected in $BRANCH. Skipping. Please commit or stash changes first."
        FAILED_BRANCHES+=("$BRANCH")
        continue
    fi

    # Pull latest changes for this branch
    print_status "Pulling latest changes for $BRANCH..."
    git pull origin "$BRANCH" || true

    # Check if the branch is already up-to-date with MAIN_BRANCH
    if git merge-base --is-ancestor "$MAIN_BRANCH" "$BRANCH" 2>/dev/null; then
        print_warning "Branch $BRANCH is already up-to-date with $MAIN_BRANCH. Skipping merge."
        SUCCESSFUL_BRANCHES+=("$BRANCH")
        continue
    fi

    # Attempt to merge main
    print_status "Merging $MAIN_BRANCH into $BRANCH..."

    if git merge "$MAIN_BRANCH" --no-edit; then
        print_success "Merge successful for $BRANCH"

        # Push the changes
        print_status "Pushing $BRANCH..."
        if git push origin "$BRANCH"; then
            print_success "Successfully pushed $BRANCH"
            SUCCESSFUL_BRANCHES+=("$BRANCH")
        else
            print_error "Failed to push $BRANCH"
            FAILED_BRANCHES+=("$BRANCH")
        fi
    else
        print_warning "Merge conflict detected in $BRANCH"

        # Abort the merge
        git merge --abort
        print_status "Merge aborted for $BRANCH"
        CONFLICT_BRANCHES+=("$BRANCH")
    fi

    echo # Empty line for readability
done

# Return to original branch
print_status "Returning to original branch: $ORIGINAL_BRANCH"
git checkout "$ORIGINAL_BRANCH"

# Run npm install if npm is available and package.json exists
if command -v npm >/dev/null 2>&1 && [ -f "package.json" ]; then
    print_status "Running npm install..."
    if npm install; then
        print_success "npm install successful"
    else
        print_error "npm install failed"
        exit 1
    fi
fi

# Print summary
echo
print_status "=== SUMMARY ==="

if [ ${#SUCCESSFUL_BRANCHES[@]} -gt 0 ]; then
    print_success "Successfully updated and pushed (${#SUCCESSFUL_BRANCHES[@]}):"
    printf '%s\n' "${SUCCESSFUL_BRANCHES[@]}" | sed 's/^/  ✓ /'
fi

if [ ${#CONFLICT_BRANCHES[@]} -gt 0 ]; then
    print_warning "Branches with conflicts (${#CONFLICT_BRANCHES[@]}):"
    printf '%s\n' "${CONFLICT_BRANCHES[@]}" | sed 's/^/  ⚠ /'
    echo -e "${YELLOW}These branches need manual conflict resolution${NC}"
fi

if [ ${#FAILED_BRANCHES[@]} -gt 0 ]; then
    print_error "Branches that failed (${#FAILED_BRANCHES[@]}):"
    printf '%s\n' "${FAILED_BRANCHES[@]}" | sed 's/^/  ✗ /'
fi

echo
print_status "Operation completed!"

# Exit with appropriate code
if [ ${#FAILED_BRANCHES[@]} -gt 0 ]; then
    exit 1
elif [ ${#CONFLICT_BRANCHES[@]} -gt 0 ]; then
    exit 2
else
    exit 0
fi