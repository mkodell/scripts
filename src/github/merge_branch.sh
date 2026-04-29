#!/bin/bash

source "$(git -C "$(dirname "$0")" rev-parse --show-toplevel)/.env"

FEATURE_BRANCH="$1"
FIX_VERSION="$2"

# Extracts ticket and pr number from branch name
TICKET=$(echo "$FEATURE_BRANCH" | grep -oE '^[A-Z]+-[0-9]+')
PR_NUMBER=$(gh pr list --head "$BRANCH" --json number -q .number)

# Gets token from cli?
GITHUB_TOKEN=$(gh auth token)

### === Check master is not building ===
./scripts/github_pr_checker.sh master

echo "Master is clear. Proceeding with merge..."

### === MERGE STEP ===
echo "Merging '$FEATURE_BRANCH' into '$BASE_BRANCH'..."

MERGE_RESPONSE=$(gh api \
  -X POST \
  -H "Accept: application/vnd.github+json" \
  "/repos/$REPO/merges" \
  -f base="$BASE_BRANCH" \
  -f head="$FEATURE_BRANCH" \
  -f commit_message="Merge pull request #$PR_NUMBER from sourcetoad/$FEATURE_BRANCH" \
  2>&1)

# Check for success
if echo "$MERGE_RESPONSE" | grep -q '"sha":'; then
    echo "✅ Merge successful."
else
    echo "❌ Merge failed: $MERGE_RESPONSE"
    exit 1
fi

osascript -e 'display notification "'"$FEATURE_BRANCH"' has been merged into '"$BASE_BRANCH"'!" with title "Github Watcher"' -e 'do shell script "afplay /System/Library/Sounds/Glass.aiff"'

sleep 10

# Run master watcher
./scripts/github_pr_checker.sh master

# Check if master watcher succeeded
if [[ $? -ne 0 ]]; then
  echo "github_pr_checker.sh failed, stopping."
  exit 1
fi

# Run Jira mover
./scripts/jira_move.sh $TICKET "In QA" "ReadyForQA" $FIX_VERSION

echo "Full process complete."
