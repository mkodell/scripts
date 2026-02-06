#!/bin/bash

# ---------------- setup ----------------

mkdir -p "$(dirname "$WATCHED_KEYS")"
touch "$WATCHED_KEYS"

# ---------------- args ----------------

COMMAND="$1"

if [[ "$COMMAND" == "--run" ]]; then
  START="$2"
fi

if [[ "$COMMAND" == "--print" ]]; then
  START="$2"
  END="$3"
  SPRINT="$4"
fi

# ---------------- helpers ----------------

format_date() {
  local d="$1"
  [ "$d" = "-" ] && { echo "-"; return; }
  d=${d%%T*}
  date -j -f "%Y-%m-%d" "$d" "+%m-%d-%Y" 2>/dev/null || date -d "$d" "+%m-%d-%Y"
}

weekday_duration() {
  local started="$1"
  local closed="$2"

  [ "$started" = "-" ] && { echo "-"; return; }

  local today end_date start_sec end_sec cur_sec dow workdays=0
  today=$(date "+%m-%d-%Y")
  end_date="$closed"
  [ "$closed" = "-" ] && end_date="$today"

  start_sec=$(date -j -f "%m-%d-%Y" "$started" "+%s" 2>/dev/null || date -d "$started" "+%s")
  end_sec=$(date -j -f "%m-%d-%Y" "$end_date" "+%s" 2>/dev/null || date -d "$end_date" "+%s")

  cur_sec=$start_sec
  while (( cur_sec < end_sec )); do
    dow=$(date -j -f "%s" "$cur_sec" "+%u" 2>/dev/null || date -d "@$cur_sec" "+%u")
    (( dow <= 5 )) && ((workdays++))
    ((cur_sec += 86400))
  done

  [[ "$closed" == "-" ]] && echo "$workdays days (ongoing)" || echo "$workdays days"
}

colorize() {
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
}

NR==1 {
  print BOLD $0 RESET
  next
}

{
  # ---- STATUS ----
  gsub(/In_Progress|Code_Review|In_QA/, YELLOW "&" RESET)
  gsub(/Closed/, GREEN "&" RESET)

  # ---- KEY PREFIX ----
  if ($1 ~ /^ODA-/)      sub(/^ODA-[^ ]*/, LIGHT_GREEN "&" RESET)
  else if ($1 ~ /^EJA-/) sub(/^EJA-[^ ]*/, BLUE "&" RESET)
  else if ($1 ~ /^HXA-/) sub(/^HXA-[^ ]*/, GOLD "&" RESET)
  else if ($1 ~ /^VA-|^VITV-|^VKK-|^VKNG-/) sub(/^[^ ]*/, PURPLE "&" RESET)
  else if ($1 ~ /^ARA-/) sub(/^ARA-[^ ]*/, RED "&" RESET)
  
  print
}'
}

render_table() {
  local json="$1"
  local color="$2"

  jq -r '
    ["KEY","NAME","STATUS","ESTIMATE","VERSION","STARTED_AT","CLOSED_AT","DURATION","NOTES"],
    (.issues[] | [
      .key,
      .fields.summary,
      (.fields.status.name | gsub(" ";"_")),
      (.fields.customfield_10004 // "-"),
      (if (.fields.fixVersions|length)>0 then (.fields.fixVersions|map(.name)|join(",")) else "-" end),
      (.fields.customfield_11605 // "-"),
      (.fields.resolutiondate // "-"),
      "",
      ""
    ]) | @tsv
  ' <<< "$json" |

  while IFS=$'\t' read -r key name status estimate version started closed duration notes; do
    if [[ "$key" == "KEY" ]]; then
      printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
        "$key" "$name" "$status" "$estimate" "$version" "$started" "$closed" "$duration" "$notes"
      continue
    fi
    
    started=$(format_date "$started")
    closed=$(format_date "$closed")
    estimate=${estimate%%.*}
    duration=$(weekday_duration "$started" "$closed")

    printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
      "$key" "$name" "$status" "$estimate" "$version" "$started" "$closed" "$duration" "$notes"
  done |
  awk -F'\t' '
    NR==1 { print "0\t"$0; next }
    {
      order=99
      if ($3=="Open") order=1
      else if ($3=="In_Progress") order=2
      else if ($3=="Code_Review") order=3
      else if ($3=="In_QA") order=4
      else if ($3=="Closed") order=5
      print order "\t" $0
    }' |
  sort -n |
  cut -f2- |
  column -t -s $'\t' |
  { [[ "$color" == "true" ]] && colorize || cat; }
}

# ---------------- command handlers ----------

case "$COMMAND" in
  --add)
    shift
    for key in "$@"; do
      [[ "$key" =~ ^[A-Z]+-[0-9]+$ ]] || { echo "Invalid key: $key"; exit 1; }
      echo "$key" >> "$WATCHED_KEYS"
    done
    sort -u "$WATCHED_KEYS" -o "$WATCHED_KEYS"
    echo "Watched keys:"
    cat "$WATCHED_KEYS"
    exit 0
    ;;

  --remove)
    shift
    for key in "$@"; do
      sed -i '' "/^$key$/d" "$WATCHED_KEYS"
    done
    echo "Watched keys:"
    cat "$WATCHED_KEYS"
    exit 0
    ;;
    
  --list)
    if [[ ! -s "$WATCHED_KEYS" ]]; then
      echo "No watched keys."
    else
      echo "Watched keys:"
      cat "$WATCHED_KEYS"
    fi
    exit 0
    ;;

  --reset)
    > "$WATCHED_KEYS"
    echo "All watched keys cleared."
    exit 0
    ;;
    
  --run)
    ;;
esac

# ---------------- jira fetch ----------------

ISSUE_KEYS=$(cat "$WATCHED_KEYS" | jq -R -s -c 'split("\n") | map(select(length > 0))')

if [[ "$ISSUE_KEYS" == "[]" ]]; then
    echo "No watched keys. Use --add KEY first."
    exit 1
fi

FURTHER_DETAILS=$(curl -s \
  --request POST \
  --url "$JIRA_URL/rest/api/3/issue/bulkfetch" \
  --user "$EMAIL:$API_TOKEN" \
  --header 'Accept: application/json' \
  --header 'Content-Type: application/json' \
  --data @- <<EOF
{
  "expand": ["names", "changelog"],
  "fields": ["*all"],
  "fieldsByKeys": false,
  "issueIdsOrKeys": $ISSUE_KEYS,
  "properties": []
}
EOF
)

REGULAR_COUNT=$(jq '.issues | length' <<< "$FURTHER_DETAILS")

ROLLOVER_DETAILS=$(
jq --arg START "$START" '
  .issues |= map(select(.fields.customfield_11605 < $START))
' <<< "$FURTHER_DETAILS"
)

ROLLOVER_COUNT=$(jq '.issues | length' <<< "$ROLLOVER_DETAILS")

# ---------------- outputs ----------------

OUTPUT=$(render_table "$FURTHER_DETAILS" false)
ROLLOVERS=$(render_table "$ROLLOVER_DETAILS" false)

TERMINAL_OUTPUT=$(render_table "$FURTHER_DETAILS" true)
TERMINAL_ROLLOVERS=$(render_table "$ROLLOVER_DETAILS" true)

echo "$TERMINAL_OUTPUT"
echo "Total Issues: $REGULAR_COUNT"
echo ""
echo "Rollovers from previous sprint:"
echo "$TERMINAL_ROLLOVERS"
echo "Total Rollover Issues: $ROLLOVER_COUNT"

if [[ "$COMMAND" == "--print" ]]; then
  FORMATTED_START=$(format_date "$START")
  FORMATTED_END=$(format_date "$END")

  {
    echo "$SPRINT ($FORMATTED_START - $FORMATTED_END)"
    echo "$OUTPUT"
    echo "Total Issues: $REGULAR_COUNT"
    echo ""
    echo "Rollovers from previous sprint:"
    echo "$ROLLOVERS"
    echo "Total Rollover Issues: $ROLLOVER_COUNT"
    echo ""
    echo ""
  } >> "$LOG_PATH"
fi
