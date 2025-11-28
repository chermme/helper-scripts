#!/bin/bash

# PR Status Checker
# Lists all open PRs with approval status, conflicts, and comments

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "Fetching your open PRs..."
echo ""

# Get all open PRs for the current user
prs=$(gh pr list --author "@me" --state open --json number,title,headRefName,reviewDecision,mergeable,url)

# Check if there are any PRs
if [ "$(echo "$prs" | jq '. | length')" -eq 0 ]; then
    echo "No open PRs found."
    exit 0
fi

# Iterate through each PR
echo "$prs" | jq -r '.[] | @base64' | while read -r pr; do
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
    case "$review_decision" in
        "APPROVED")
            echo -e "${GREEN}✓ APPROVED${NC}"
            # Get reviewers who approved
            reviewers=$(gh pr view "$number" --json reviews --jq '.reviews[] | select(.state == "APPROVED") | .author.login' | sort -u | tr '\n' ', ' | sed 's/,$//')
            echo "  Approved by: $reviewers"
            ;;
        "CHANGES_REQUESTED")
            echo -e "${RED}✗ CHANGES REQUESTED${NC}"
            # Get reviewers who requested changes
            reviewers=$(gh pr view "$number" --json reviews --jq '.reviews[] | select(.state == "CHANGES_REQUESTED") | .author.login' | sort -u | tr '\n' ', ' | sed 's/,$//')
            echo "  Changes requested by: $reviewers"
            ;;
        "REVIEW_REQUIRED"|"")
            echo -e "${YELLOW}⚠ REVIEW REQUIRED${NC}"
            ;;
        *)
            echo -e "${YELLOW}⚠ $review_decision${NC}"
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
    unresolved=$(gh pr view "$number" --json reviewThreads --jq '[.reviewThreads[] | select(.isResolved == false)] | length')
    total=$(gh pr view "$number" --json reviewThreads --jq '.reviewThreads | length')
    
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
    
    echo ""
done

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "Summary:"
total_prs=$(echo "$prs" | jq '. | length')
approved=$(echo "$prs" | jq '[.[] | select(.reviewDecision == "APPROVED")] | length')
conflicting=$(echo "$prs" | jq '[.[] | select(.mergeable == "CONFLICTING")] | length')

echo "Total open PRs: $total_prs"
echo -e "Approved: ${GREEN}$approved${NC}"
echo -e "With conflicts: ${RED}$conflicting${NC}"