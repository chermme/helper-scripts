#!/bin/bash

# Get the list of files changed in the current branch compared to main/master
# First, try to find the default branch name
default_branch=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')

# If that doesn't work, try common branch names
if [ -z "$default_branch" ]; then
    if git show-ref --verify --quiet refs/heads/main; then
        default_branch="main"
    elif git show-ref --verify --quiet refs/heads/master; then
        default_branch="master"
    else
        echo "Error: Could not determine default branch (main/master)"
        exit 1
    fi
fi

echo "Comparing against branch: $default_branch"

# Get all changed files (added, modified, or deleted but still in working tree)
changed_files=$(git diff --name-only "$default_branch"...HEAD)

# Check if there are any changed files
if [ -z "$changed_files" ]; then
    echo "No files changed in current branch compared to $default_branch"
    exit 0
fi

# Count files
file_count=$(echo "$changed_files" | wc -l)
echo "Opening $file_count changed file(s) in VSCode..."

# Build array of files that exist
files_to_open=()
while IFS= read -r file; do
    if [ -f "$file" ]; then
        files_to_open+=("$file")
    else
        echo "  ✗ $file (file not found, may have been deleted)"
    fi
done <<< "$changed_files"

# Open all files at once in VSCode (they'll open as separate tabs)
if [ ${#files_to_open[@]} -gt 0 ]; then
    code "${files_to_open[@]}"
    for file in "${files_to_open[@]}"; do
        echo "  ✓ $file"
    done
else
    echo "No files to open"
fi

echo "Done!"