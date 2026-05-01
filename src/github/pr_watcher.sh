#!/bin/bash

source "$(git -C "$(dirname "$0")" rev-parse --show-toplevel)/.env"

TARGET="$1"

if [[ -z "$TARGET" ]]; then
    echo "Usage: $0 <PR number or branch name>"
    exit 1
fi

HEAD_SHA=$(gh api "repos/$REPO/commits/$TARGET" --jq '.sha')

echo "Checking PR #$TARGET (SHA: ${HEAD_SHA:0:7})..."
echo "Watching..."

STABLE_COUNT=0
REQUIRED_STABLE=3

while true; do
    CHECKS_JSON=$(gh api "repos/$REPO/commits/$HEAD_SHA/check-runs")

    TOTAL=$(echo "$CHECKS_JSON" | jq '.check_runs | length')
    PENDING=$(echo "$CHECKS_JSON" | jq '[.check_runs[] | select(.status != "completed")] | length')
    FAILED=$(echo "$CHECKS_JSON" | jq '[.check_runs[] | select(.status == "completed" and .conclusion != "success" and .conclusion != "skipped" and .conclusion != "neutral")] | length')
    SUCCEEDED=$(echo "$CHECKS_JSON" | jq '[.check_runs[] | select(.status == "completed" and (.conclusion == "success" or .conclusion == "skipped" or .conclusion == "neutral"))] | length')

    echo "[$(date +%H:%M:%S)] Total: $TOTAL | Pending: $PENDING | ✅ $SUCCEEDED | ❌ $FAILED"

    if [[ "$PENDING" -eq 0 && "$TOTAL" -gt 0 ]]; then
        ((STABLE_COUNT++))
        echo "  (stable for $STABLE_COUNT/$REQUIRED_STABLE polls)"
        if [[ "$STABLE_COUNT" -ge "$REQUIRED_STABLE" ]]; then
            if [[ "$FAILED" -gt 0 ]]; then
                FAILED_NAMES=$(echo "$CHECKS_JSON" | jq -r '[.check_runs[] | select(.status == "completed" and .conclusion != "success" and .conclusion != "skipped" and .conclusion != "neutral") | .name] | join(", ")')
                echo "❌ Builds finished with $FAILED failure(s): $FAILED_NAMES"
                osascript -e 'display notification "'"$TARGET"' has failing builds!" with title "GitHub Watcher"' -e 'do shell script "afplay /System/Library/Sounds/Basso.aiff"'
            else
                echo "🎉 All builds completed successfully!"
                osascript -e 'display notification "'"$TARGET"' — all builds passed!" with title "GitHub Watcher"' -e 'do shell script "afplay /System/Library/Sounds/Glass.aiff"'
            fi
            break
        fi
    else
        STABLE_COUNT=0
    fi

    sleep 15
done

echo "Watcher finished."
exit 0
