#!/bin/bash

TARGET="$1" # PR number or branch

PREV_PENDING=-1 # initialize to -1 so the first poll always prints

if [[ -z "$TARGET" ]]; then
    echo "Usage: $0 <PR number or branch name>"
    exit 1
fi

# Input is a branch name
HEAD_SHA=$(gh api "repos/$REPO/commits/$TARGET" --jq '.sha')

while true; do
    # Now fetch check runs for $HEAD_SHA
    CHECKS_JSON=$(gh api "repos/$REPO/commits/$HEAD_SHA/check-runs")

    # Count pending check runs
    PENDING=$(echo "$CHECKS_JSON" | jq '[.check_runs[] | select(.status != "completed")] | length')

    if [[ $PREV_PENDING -eq -1 ]]; then
        echo "Checking PR #$TARGET..."
        echo "🚧 Initial pending builds: $PENDING"
        echo "Watching..."
    elif [[ $PENDING -lt $PREV_PENDING ]]; then
        echo "✅ Pending builds decreased: $PENDING remaining"
        echo "Watching..."
    fi

    PREV_PENDING=$PENDING

    if [[ "$PENDING" -eq 0 ]]; then
        echo "🎉 All builds completed!"
        osascript -e 'display notification "'"$TARGET"' has no builds running!" with title "GitHub Watcher"' -e 'do shell script "afplay /System/Library/Sounds/Glass.aiff"'
        break
    fi
    
    sleep 5
done

echo "Watcher finished."
exit 0
