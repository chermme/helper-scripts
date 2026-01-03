# GitHub Copilot Instructions for Helper Scripts

## Project Overview
This repository contains a collection of shell scripts for automating common development workflows, primarily focused on Git operations, Docker management, and macOS utilities.

## Code Style and Conventions

### Shell Script Standards
- **Shebang**: Use `#!/usr/bin/env bash` for Bash scripts or `#!/bin/zsh` for Zsh-specific scripts
- **File naming**: Use lowercase with underscores (e.g., `git_branch_sync.sh`, `docker-update-all.sh`)
- **Executable permissions**: All scripts should be executable (`chmod +x`)
- **Bash Compatibility**: All Bash scripts must be compatible with **Bash 3.2** (macOS default version)
  - Avoid Bash 4+ features like associative arrays (`declare -A`)
  - Use indexed arrays only: `array=()` and `array+=("item")`
  - Avoid `[[` with `=~` regex when capturing groups in `BASH_REMATCH` (works but be cautious)
  - Do not use features like: `&>>`, `|&`, `**` globstar (unless `shopt -s globstar`)
  - Test scripts on macOS or with Bash 3.2 before committing

### Code Structure
1. **Configuration Section**: Place all configurable variables at the top with clear comments
   ```bash
   # ====================================
   # CONFIGURATION
   # ====================================
   ```

2. **Utility Functions Section**: Group utility functions together
   ```bash
   # ====================================
   # UTILITY FUNCTIONS
   # ====================================
   ```

3. **Main Logic**: Implement core functionality after helper functions

### Variable Naming
- Use `UPPER_SNAKE_CASE` for constants and configuration variables
- Use `lower_snake_case` for local variables and function names
- Use descriptive names: `MAIN_BRANCH`, `DRY_RUN`, `EXCLUDED_BRANCHES`

### Output and User Feedback

#### Color-Coded Messages
Always use color-coded output functions for user feedback:
```bash
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
```

#### Message Guidelines
- `print_status`: For informational messages about current operations
- `print_success`: For successful completion of operations
- `print_warning`: For non-critical issues or warnings
- `print_error`: For errors that require attention
- `print_dry_run`: For dry-run mode operations

### Error Handling

#### Exit Codes
- `0`: Success
- `1`: General errors (e.g., not in a Git repository, missing requirements)
- `2`: Specific operation failures

#### Validation
- Always validate prerequisites before executing main logic
- Check if commands/tools are available before using them
- Verify working directory state when necessary
- Use descriptive error messages

Example:
```bash
if [ -z "$REPO_ROOT" ]; then
    echo "Error: Not in a Git repository"
    exit 1
fi
```

### Feature Flags and Options

#### Environment Variables
Support environment variable configuration for common options:
- `DRY_RUN`: Set to `true` for dry-run mode (default: `false`)
- `VERBOSE`: Set to `true` for detailed output (default: `false`)
- `NO_PUSH`: Set to `true` to prevent remote operations (default: `false`)

Example:
```bash
DRY_RUN="${DRY_RUN:-false}"
VERBOSE="${VERBOSE:-false}"
```

#### Command-Line Arguments
- Use positional parameters with defaults: `MAIN_BRANCH="${1:-main}"`
- Document usage in script comments at the top

### Git Hook Management

When scripts perform automated Git operations, implement hook deactivation:

```bash
HOOKS_TO_DEACTIVATE=("post-checkout" "post-merge" "pre-commit")
DEACTIVATED_HOOKS=()

deactivate_git_hooks() {
    local git_hooks_dir=".git/hooks"
    # ... implementation
}

reactivate_git_hooks() {
    # ... implementation
}

cleanup_on_exit() {
    reactivate_git_hooks
}

# Set up trap to ensure cleanup
trap cleanup_on_exit EXIT
```

### Arrays and Data Tracking

Use arrays to track results and state:
```bash
IGNORED_BRANCHES=()
SUCCESSFUL_BRANCHES=()
FAILED_BRANCHES=()

# Add items
SUCCESSFUL_BRANCHES+=("$branch")

# Check length
if [ ${#FAILED_BRANCHES[@]} -eq 0 ]; then
    # No failures
fi
```

### Git Operations

#### Branch Operations
- Use `git branch --format='%(refname:short)'` for listing branches
- Use `git rev-parse --show-toplevel` to get repository root
- Use `git branch --show-current` to get current branch

#### Quiet Operations
- Use `--quiet` flag for operations that don't need output
- Suppress output with `2>/dev/null` when checking for existence

#### Remote Operations
- Always fetch before operations: `git fetch --all --quiet`
- Check if remote branches exist before pulling
- Handle missing remotes gracefully

### GitHub CLI Integration

Use `gh` CLI for GitHub operations:
```bash
# Check if gh CLI is available
if command -v gh &> /dev/null; then
    # Use gh commands
    gh pr view "$PR_NUMBER" --json files --jq '.files[].path'
fi
```

Common patterns:
- `gh pr view <number> --json <fields> --jq '<query>'`
- `gh api repos/<owner>/<repo> --jq '<query>'`

### Docker Operations

For Docker scripts:
- Always verify Docker is running before operations
- Check return codes and handle errors appropriately
- Use descriptive output for each operation
- Handle missing/unavailable images gracefully

Example:
```bash
DOCKER_INFO_OUTPUT=$(docker info 2> /dev/null | grep "Containers:" | awk '{print $1}')
if [ "$DOCKER_INFO_OUTPUT" != "Containers:" ]; then
    echo "Docker is not running, exiting"
    exit 1
fi
```

### Path and Directory Handling

- Use absolute paths when possible: `SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"`
- Use `$HOME` for user home directory references
- Create directories with `mkdir -p` to ensure parent directories exist

### Comments and Documentation

#### Script Headers
Include a brief description at the top of the script:
```bash
#!/usr/bin/env bash

# PR Status Checker
# Lists PR status with approval status, conflicts, and comments
#
# Usage:
#   script.sh          - Default behavior
#   script.sh all      - Show all
#   script.sh <param>  - Specific operation
```

#### Section Comments
Use clear section dividers:
```bash
# ============================================================================
# Section Name
# ============================================================================
```

#### Function Comments
Document complex functions:
```bash
# Extract the parent ticket number from a stacked branch name
# Example: stacked/br1234/BR-2345-my-feature -> br1234
# Returns empty string if branch doesn't follow the correct pattern
extract_parent_ticket() {
    # ...
}
```

### Testing and Dry-Run Support

Always support dry-run mode for destructive operations:
```bash
if [ "$DRY_RUN" = true ]; then
    print_dry_run "Would perform action: $action"
else
    # Perform actual action
    perform_action
fi
```

### Regular Expressions

Use Bash regex matching for pattern validation:
```bash
if [[ "$branch" =~ ^stacked/([^/]+)/(.+)$ ]]; then
    parent="${BASH_REMATCH[1]}"
    feature="${BASH_REMATCH[2]}"
fi
```

## Project-Specific Patterns

### Ticket Extraction
Scripts that work with branch names should support ticket extraction:
- Pattern: `[A-Z]+-[0-9]+` (e.g., `BR-1234`, `JIRA-5678`)
- Normalize tickets for comparison (lowercase, remove special chars)

### Stacked Branches
Support for stacked branch workflows:
- Pattern: `stacked/<parent-ticket>/<branch-name>`
- Extract parent ticket for dependency management

### Backup Branches
When creating backups:
- Pattern: `backup/<date>/<time>/<original-branch-name>`
- Date format: `YYYY-MM-DD/HH-MM-SS`

### Workspace Management
For cross-machine sync:
- Use unique repository identifiers based on remote URL
- Store state in `$HOME/.git-workspaces/<repo-id>/`
- Track current branch and all local branches

## Testing Scripts

When creating or modifying scripts:
1. Test with dry-run mode first
2. Test error conditions (missing tools, dirty working directory, etc.)
3. Test with both standard and edge-case branch names
4. Verify cleanup functions are called on exit

## Security Considerations

- Never hardcode credentials or sensitive information
- Use environment variables for sensitive configuration
- Validate all user inputs
- Be cautious with `sudo` commands (document why needed)
- Use `shellcheck` to identify common issues

## Tool Dependencies

Scripts may depend on:
- **Git**: Core functionality
- **GitHub CLI (`gh`)**: GitHub operations
- **Docker**: Container management
- **Jira CLI (`jira`)**: Optional Jira integration
- **jq**: JSON parsing
- **Standard Unix utilities**: awk, sed, grep, etc.

Always check for tool availability before use and provide helpful error messages when missing.

## macOS Specific

For macOS scripts:
- Use `chflags` for file/app attributes
- Use `killall` to restart system services (e.g., Dock)
- Consider compatibility with different macOS versions
- Document any required permissions (e.g., Full Disk Access)
