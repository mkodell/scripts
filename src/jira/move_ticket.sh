#!/bin/bash

source "$(git -C "$(dirname "$0")" rev-parse --show-toplevel)/.env"

ISSUE_KEY="$1"
TARGET_STATUS="${2}" # Default: "In QA"
NEW_LABEL="${3}" # Default label if status is In QA
FIX_VERSION_NAME="${4}" # Default fix version if status is In QA

# ====== 1. Get transition ID ======
TRANSITION_ID=$(curl -s -u $EMAIL:$API_TOKEN -X GET \
  -H "Content-Type: application/json" \
  "$JIRA_URL/rest/api/2/issue/$ISSUE_KEY/transitions" | \
  jq -r --arg STATUS "$TARGET_STATUS" '.transitions[] | select(.to.name==$STATUS) | .id')

if [[ -z "$TRANSITION_ID" ]]; then
  echo "Error: Could not find transition for status '$TARGET_STATUS'"
  osascript -e 'display notification "'"$ISSUE_KEY"' could not be updated" with title "Jira Watcher"' -e 'do shell script "afplay /System/Library/Sounds/Glass.aiff"'
  exit 1
fi

# ====== 2. Build fields to update ======
UPDATE_FIELDS_JSON="{}"  # Start with empty JSON

# Only modify fields if target status is In QA
if [[ "$TARGET_STATUS" == "In QA" ]]; then
    # ---- Unassign ----
    UPDATE_FIELDS_JSON='{"assignee": null}'

    # ---- Labels ----
    EXISTING_LABELS=$(curl -s -u $EMAIL:$API_TOKEN -X GET \
      -H "Content-Type: application/json" \
      "$JIRA_URL/rest/api/2/issue/$ISSUE_KEY" | jq -r '.fields.labels | join(",")')

    if [[ -z "$EXISTING_LABELS" ]]; then
      LABELS_JSON="[\"$NEW_LABEL\"]"
    else
      if [[ ",$EXISTING_LABELS," == *",$NEW_LABEL,"* ]]; then
        LABELS_JSON=$(jq -n --arg labels "$EXISTING_LABELS" '$labels | split(",")')
      else
        LABELS_JSON=$(jq -n --arg labels "$EXISTING_LABELS" --arg new "$NEW_LABEL" '($labels | split(",")) + [$new]')
      fi
    fi

    UPDATE_FIELDS_JSON=$(jq -n --argjson base "$UPDATE_FIELDS_JSON" --argjson labels "$LABELS_JSON" \
      '$base + {labels: $labels}')

    # ---- Optional Fix Version ----
    if [[ -n "$FIX_VERSION_NAME" ]]; then
        PROJECT_KEY=$(curl -s -u $EMAIL:$API_TOKEN -X GET \
          -H "Content-Type: application/json" \
          "$JIRA_URL/rest/api/2/issue/$ISSUE_KEY" | jq -r '.fields.project.key')

        FIX_VERSION_ID=$(curl -s -u $EMAIL:$API_TOKEN -X GET \
          -H "Content-Type: application/json" \
          "$JIRA_URL/rest/api/2/project/$PROJECT_KEY/versions" | \
          jq -r --arg VERSION "$FIX_VERSION_NAME" '.[] | select(.name==$VERSION) | .id')

        if [[ -n "$FIX_VERSION_ID" ]]; then
            UPDATE_FIELDS_JSON=$(jq -n --argjson base "$UPDATE_FIELDS_JSON" \
              --argjson fixVersions "[{\"id\":\"$FIX_VERSION_ID\"}]" \
              '$base + {fixVersions: $fixVersions}')
        else
            echo "Warning: Fix version '$FIX_VERSION_NAME' not found, skipping."
        fi
    fi
fi

# ====== 3. Update issue ======
curl -s -u $EMAIL:$API_TOKEN -X PUT \
  -H "Content-Type: application/json" \
  -d '{"fields": '"$UPDATE_FIELDS_JSON"'}' \
  "$JIRA_URL/rest/api/2/issue/$ISSUE_KEY"

# ====== 4. Move issue ======
curl -s -u $EMAIL:$API_TOKEN -X POST \
  -H "Content-Type: application/json" \
  -d '{"transition": {"id": "'"$TRANSITION_ID"'"}}' \
  "$JIRA_URL/rest/api/2/issue/$ISSUE_KEY/transitions"


if [[ $NEW_LABEL && $FIX_VERSION_NAME ]]; then
    echo "Issue $ISSUE_KEY updated; version set, label added, unassigned, and moved to '$TARGET_STATUS' successfully!"
else
    echo "Issue $ISSUE_KEY updated; moved to '$TARGET_STATUS' successfully!"
fi

osascript -e 'display notification "'"$ISSUE_KEY"' has been updated!" with title "Jira Watcher"' -e 'do shell script "afplay /System/Library/Sounds/Glass.aiff"'
