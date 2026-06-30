#!/bin/bash

source "$(git -C "$(dirname "$0")" rev-parse --show-toplevel)/.env"

GITHUB_TOKEN=$(gh auth token)
 
# ---------------- setup ----------------
 
mkdir -p "$(dirname "$WATCHED_KEYS")"
touch "$WATCHED_KEYS"
 
# ---------------- helpers ----------------
 
colorize_table() {
awk '
BEGIN {
  RESET="\033[0m"
  BOLD="\033[1m"
  RED="\033[38;5;124m"
  LIGHT_GREEN="\033[0;92m"
  GREEN="\033[32m"
  GOLD="\033[38;5;94m"
  BLUE="\033[38;5;45m"
  PURPLE="\033[38;5;54m"
  YELLOW="\033[0;93m"
  GRAY="\033[0;90m"
}

NR==1 {
  print BOLD $0 RESET
  next
}

{
  # ---- KEY PREFIX ----
  if ($1 ~ /^ODA-/)      sub(/^ODA-[^ ]*/, LIGHT_GREEN "&" RESET)
  else if ($1 ~ /^EJA-/) sub(/^EJA-[^ ]*/, BLUE "&" RESET)
  else if ($1 ~ /^HXA-/) sub(/^HXA-[^ ]*/, GOLD "&" RESET)
  else if ($1 ~ /^VA-|^VITV-|^VKK-|^VKNG-/) sub(/^[^ ]*/, PURPLE "&" RESET)
  else if ($1 ~ /^ARA-/) sub(/^ARA-[^ ]*/, RED "&" RESET)

  # ---- CHANGES & CONFLICTS ----
  gsub(/yes/, RED "yes" RESET)

  # ---- APPROVALS ---- (number preceded by 2+ spaces, not part of a key like EJA-802)
  if (match($0, /  [0-9]+/)) {
    num = substr($0, RSTART+2, RLENGTH-2)
    if (num+0 == 0)      color = GRAY
    else if (num+0 == 1) color = YELLOW
    else                 color = GREEN
    sub(/  [0-9]+/, "  " color num RESET)
  }

  print
}'
}
 
# ---------------- fetch jira issues ----------------
 
ISSUE_KEYS=$(cat "$WATCHED_KEYS" | jq -R -s -c 'split("\n") | map(select(length > 0))')
 
if [[ "$ISSUE_KEYS" == "[]" ]]; then
    echo "No watched keys. Add keys with jiraSummary --add KEY."
    exit 1
fi
 
JIRA_DATA=$(curl -s \
  --request POST \
  --url "$JIRA_URL/rest/api/3/issue/bulkfetch" \
  --user "$EMAIL:$API_TOKEN" \
  --header 'Accept: application/json' \
  --header 'Content-Type: application/json' \
  --data @- <<EOF
{
  "fields": ["summary", "status"],
  "fieldsByKeys": false,
  "issueIdsOrKeys": $ISSUE_KEYS,
  "properties": []
}
EOF
)
 
# Filter to only Code Review issues
CODE_REVIEW_ISSUES=$(jq '[.issues[] | select(.fields.status.name == "Code Review")]' <<< "$JIRA_DATA")
CODE_REVIEW_COUNT=$(jq 'length' <<< "$CODE_REVIEW_ISSUES")
 
if [[ "$CODE_REVIEW_COUNT" -eq 0 ]]; then
    echo "No watched issues currently in Code Review."
    exit 0
fi
 
# ---------------- fetch PR approvals ----------------
 
# Accumulate rows: KEY | SUMMARY | PR | APPROVALS | CHANGES | CONFLICTS
ROWS=()
 
while IFS=$'\t' read -r issue_id issue_key summary; do
    DEV_INFO=$(curl -s \
      --url "$JIRA_URL/rest/dev-status/1.0/issue/detail?issueId=${issue_id}&applicationType=oAuth-com.github.integration.production&dataType=pullrequest" \
      --user "$EMAIL:$API_TOKEN" \
      --header 'Accept: application/json')
 
    PR_COUNT=$(jq '[.detail[]?.pullRequests[]?] | length' <<< "$DEV_INFO")
 
    if [[ "$PR_COUNT" -eq 0 ]]; then
        ROWS+=("$(printf '%s\t%s\t%s\t%s\t%s\t%s' "$issue_key" "$summary" "(no PRs)" "-" "" "")")
        continue
    fi
 
    while IFS=$'\t' read -r pr_url pr_title pr_status; do
        pr_path=$(echo "$pr_url" | sed 's|https://github.com/||')
        owner=$(echo "$pr_path" | cut -d'/' -f1)
        repo=$(echo "$pr_path" | cut -d'/' -f2)
        pr_number=$(echo "$pr_path" | cut -d'/' -f4)
 
        if [[ -z "$owner" || -z "$repo" || -z "$pr_number" ]]; then
            ROWS+=("$(printf '%s\t%s\t%s\t%s\t%s\t%s' "$issue_key" "$summary" "$pr_title" "?" "" "")")
            continue
        fi

        REVIEWS=$(curl -s \
          --url "https://api.github.com/repos/${owner}/${repo}/pulls/${pr_number}/reviews" \
          --header "Authorization: Bearer $GITHUB_TOKEN" \
          --header 'Accept: application/vnd.github+json')

        PR_INFO=$(curl -s \
          --url "https://api.github.com/repos/${owner}/${repo}/pulls/${pr_number}" \
          --header "Authorization: Bearer $GITHUB_TOKEN" \
          --header 'Accept: application/vnd.github+json')

        APPROVALS=$(jq 'if type == "array" then group_by(.user.login) | map(sort_by(.submitted_at) | last) | map(select(.state == "APPROVED")) | length else 0 end' <<< "$REVIEWS")

        CHANGES=$(jq -r 'if type == "array" then group_by(.user.login) | map(sort_by(.submitted_at) | last) | map(select(.state == "CHANGES_REQUESTED")) | if length > 0 then "yes" else "" end else "" end' <<< "$REVIEWS")

        CONFLICTS=$(jq -r 'if .mergeable == false then "yes" else "" end' <<< "$PR_INFO")

        ROWS+=("$(printf '%s\t%s\t%s\t%s\t%s\t%s' "$issue_key" "$summary" "$pr_title" "$APPROVALS" "$CHANGES" "$CONFLICTS")")
 
    done < <(jq -r '
      .detail[]?.pullRequests[]? |
      [.url, .name, .status] | @tsv
    ' <<< "$DEV_INFO")
 
done < <(jq -r '.[] | [.id, .key, .fields.summary] | @tsv' <<< "$CODE_REVIEW_ISSUES")
 
# ---------------- render table ----------------
 
{
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "KEY" "SUMMARY" "PR" "APPROVALS" "CHANGE_REQUEST" "CONFLICTS"
    for row in "${ROWS[@]}"; do
        echo "$row"
    done
} |
column -t -s $'\t' |
colorize_table
 
echo ""
