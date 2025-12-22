#!/bin/bash

# PR Status Checker
# Lists PR status with approval status, conflicts, and comments
#
# Usage:
#   gh_pr_statuses.sh          - Show PR for current branch
#   gh_pr_statuses.sh all      - Show all open PRs
#   gh_pr_statuses.sh <ticket> - Show PR containing ticket number in branch name

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to display PR details
show_pr_details() {
    local pr="$1"
    
    _jq() {
        echo "$pr" | base64 --decode | jq -r "$1"
    }
    
    number=$(_jq '.number')
    title=$(_jq '.title')
    branch=$(_jq '.headRefName')
    review_decision=$(_jq '.reviewDecision')
    mergeable=$(_jq '.mergeable')
    url=$(_jq '.url')
    
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}PR #${number}${NC}: ${title}"
    echo -e "Branch: ${branch}"
    echo -e "URL: ${url}"
    echo ""
    
    # Check approval status
    echo -n "Approval Status: "
    
    # Get all reviews data once
    reviews_data=$(gh pr view "$number" --json reviews)
    
    # Check current approvers (state == APPROVED)
    current_approvers=$(echo "$reviews_data" | jq -r '.reviews[] | select(.state == "APPROVED") | .author.login' | sort -u | tr '\n' ', ' | sed 's/,$//')
    
    # Check dismissed approvals (previously approved but lost approval due to new commits/conflicts)
    dismissed_approvers=$(echo "$reviews_data" | jq -r '.reviews[] | select(.state == "DISMISSED") | .author.login' | sort -u | tr '\n' ', ' | sed 's/,$//')
    
    case "$review_decision" in
        "APPROVED")
            echo -e "${GREEN}✓ APPROVED${NC}"
            echo "  Approved by: $current_approvers"
            ;;
        "CHANGES_REQUESTED")
            echo -e "${RED}✗ CHANGES REQUESTED${NC}"
            # Get reviewers who requested changes
            change_requesters=$(echo "$reviews_data" | jq -r '.reviews[] | select(.state == "CHANGES_REQUESTED") | .author.login' | sort -u | tr '\n' ', ' | sed 's/,$//')
            echo "  Changes requested by: $change_requesters"
            if [ -n "$dismissed_approvers" ]; then
                echo -e "  ${YELLOW}ℹ Previously approved by: $dismissed_approvers${NC} (approval dismissed)"
            fi
            ;;
        "REVIEW_REQUIRED"|"")
            echo -e "${YELLOW}⚠ REVIEW REQUIRED${NC}"
            if [ -n "$dismissed_approvers" ]; then
                echo -e "  ${YELLOW}ℹ Previously approved by: $dismissed_approvers${NC} (approval dismissed)"
            fi
            ;;
        *)
            echo -e "${YELLOW}⚠ $review_decision${NC}"
            if [ -n "$dismissed_approvers" ]; then
                echo -e "  ${YELLOW}ℹ Previously approved by: $dismissed_approvers${NC} (approval dismissed)"
            fi
            ;;
    esac
    
    # Check merge conflicts
    echo -n "Merge Status: "
    case "$mergeable" in
        "MERGEABLE")
            echo -e "${GREEN}✓ No conflicts${NC}"
            ;;
        "CONFLICTING")
            echo -e "${RED}✗ HAS CONFLICTS with main${NC}"
            ;;
        "UNKNOWN")
            echo -e "${YELLOW}⚠ Status unknown (checking...)${NC}"
            ;;
        *)
            echo -e "${YELLOW}⚠ $mergeable${NC}"
            ;;
    esac
    
    # Check for unresolved review comments
    echo -n "Review Comments: "
    comments_data=$(gh pr view "$number" --json comments --jq '.comments | length')
    unresolved=$(gh pr view "$number" --json reviews --jq '[.reviews[] | select(.state == "COMMENTED" or .state == "CHANGES_REQUESTED")] | length')
    total=$comments_data
    
    if [ "$unresolved" -gt 0 ]; then
        echo -e "${YELLOW}⚠ $unresolved unresolved${NC} (of $total total)"
    elif [ "$total" -gt 0 ]; then
        echo -e "${GREEN}✓ All resolved${NC} ($total total)"
    else
        echo -e "None"
    fi
    
    # Check CI status
    echo -n "CI Status: "
    ci_status=$(gh pr view "$number" --json statusCheckRollup --jq '.statusCheckRollup[] | select(.context != null) | .state' | sort -u)
    
    if echo "$ci_status" | grep -q "FAILURE\|ERROR"; then
        echo -e "${RED}✗ FAILED${NC}"
    elif echo "$ci_status" | grep -q "PENDING"; then
        echo -e "${YELLOW}⚠ PENDING${NC}"
    elif echo "$ci_status" | grep -q "SUCCESS"; then
        echo -e "${GREEN}✓ PASSED${NC}"
    else
        echo -e "No checks"
    fi
    
    # Try to extract Jira ticket from branch name and show status
    # Looks for patterns like ABC-123, PROJ-456, etc.
    ticket_key=$(echo "$branch" | grep -oE '[A-Z]+-[0-9]+' | head -1)
    if [ -n "$ticket_key" ]; then
        echo ""
        echo -n "Jira Ticket: "
        # Check if jira CLI is available
        if command -v jira &> /dev/null; then
            jira_data=$(jira issue view "$ticket_key" --raw 2>/dev/null)
            if [ $? -eq 0 ] && [ -n "$jira_data" ]; then
                jira_status=$(echo "$jira_data" | jq -r '.fields.status.name // "Unknown"')
                jira_assignee=$(echo "$jira_data" | jq -r '.fields.assignee.displayName // "Unassigned"')
                echo -e "${BLUE}$ticket_key${NC}"
                echo "  Status: $jira_status"
                echo "  Assignee: $jira_assignee"
            else
                echo -e "${YELLOW}$ticket_key${NC} (unable to fetch from Jira)"
            fi
        else
            echo -e "${YELLOW}$ticket_key${NC} (jira CLI not installed)"
        fi
    fi
    
    echo ""
}

# Determine mode based on argument
mode="current"
search_term=""

if [ "$1" = "all" ]; then
    mode="all"
elif [ -n "$1" ]; then
    mode="search"
    search_term="$1"
fi

# Get PRs based on mode
case "$mode" in
    "current")
        current_branch=$(git branch --show-current 2>/dev/null)
        if [ -z "$current_branch" ]; then
            echo "Error: Not in a git repository or no branch checked out."
            exit 1
        fi
        echo "Fetching PR for current branch: ${current_branch}..."
        echo ""
        prs=$(gh pr list --author "@me" --state open --head "$current_branch" --json number,title,headRefName,reviewDecision,mergeable,url)
        ;;
    "all")
        echo "Fetching all your open PRs..."
        echo ""
        prs=$(gh pr list --author "@me" --state open --json number,title,headRefName,reviewDecision,mergeable,url)
        ;;
    "search")
        echo "Searching for PRs containing: ${search_term}..."
        echo ""
        prs=$(gh pr list --author "@me" --state open --json number,title,headRefName,reviewDecision,mergeable,url | jq --arg term "$search_term" '[.[] | select(.headRefName | ascii_downcase | contains($term | ascii_downcase))]')
        ;;
esac

# Check if there are any PRs
if [ "$(echo "$prs" | jq '. | length')" -eq 0 ]; then
    case "$mode" in
        "current")
            echo "No open PR found for branch: ${current_branch}"
            echo ""
            echo "Tip: Use 'pr-status all' to see all your open PRs"
            ;;
        "all")
            echo "No open PRs found."
            ;;
        "search")
            echo "No open PRs found matching: ${search_term}"
            ;;
    esac
    exit 0
fi

# Iterate through each PR
echo "$prs" | jq -r '.[] | @base64' | while read -r pr; do
    show_pr_details "$pr"
done

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# Only show summary for multiple PRs
pr_count=$(echo "$prs" | jq '. | length')
if [ "$pr_count" -gt 1 ]; then
    echo ""
    echo "Summary:"
    total_prs=$(echo "$prs" | jq '. | length')
    approved=$(echo "$prs" | jq '[.[] | select(.reviewDecision == "APPROVED")] | length')
    conflicting=$(echo "$prs" | jq '[.[] | select(.mergeable == "CONFLICTING")] | length')

    echo "Total open PRs: $total_prs"
    echo -e "Approved: ${GREEN}$approved${NC}"
    echo -e "With conflicts: ${RED}$conflicting${NC}"
fi