#!/bin/bash

# === CURRENT TIME ===
NOW=$(date +%s)

# === DELETE LOG FILE IF OLDER THAN 7 DAYS ===
if [ -f "$LOG_PATH" ]; then
    AGE_DAYS=$(( ( $NOW - $(stat -f %B "$LOG_PATH") ) / 86400 ))
    if [ $AGE_DAYS -gt 7 ]; then
        ls -l "$LOG_PATH"
        rm "$LOG_PATH"
        echo "Deleted $LOG_PATH"
        echo "[$(date)] Cleared old log file (was $AGE_DAYS days old)" >> "$LOG_PATH"
    fi
fi

echo "[$(date)] Script started" >> "$LOG_PATH"

# === GET WEATHER ===
WEATHER_JSON=$(curl -s "http://api.openweathermap.org/data/2.5/weather?q=$CITY&appid=$API_KEY&units=metric")

# Extract condition
CONDITION=$(echo "$WEATHER_JSON" | grep -o '"main":"[^"]*"' | head -1 | cut -d: -f2 | tr -d '"')
CONDITION=$(echo "$CONDITION" | tr '[:upper:]' '[:lower:]')

# Extract cloudiness (percent)
CLOUDS=$(echo "$WEATHER_JSON" | grep -o '"all":[0-9]*' | head -1 | cut -d: -f2)

# Extract sunrise and sunset timestamps
SUNRISE=$(echo "$WEATHER_JSON" | grep -o '"sunrise":[0-9]*' | cut -d: -f2)
SUNSET=$(echo "$WEATHER_JSON" | grep -o '"sunset":[0-9]*' | cut -d: -f2)

# If parsing failed, use default times
if [ -z "$SUNRISE" ] || [ -z "$SUNSET" ]; then
    SUNRISE=$(date -j -f "%H:%M" "06:00" +%s)
    SUNSET=$(date -j -f "%H:%M" "18:00" +%s)
    CONDITION="clear"
    CLOUDS=0
fi

# === DETERMINE TIME OF DAY ===
MORNING_END=$((SUNRISE + 7200))           # +2h
DAY_END=$(date -j -f "%H:%M" "12:30" +%s)
LUNCH_END=$(date -j -f "%H:%M" "13:30" +%s)
AFTERNOON_END=$((SUNSET - 3600))          # 1h before sunset
EVENING_END=$((SUNSET + 7200))            # +2h after sunset

if [ "$NOW" -ge "$SUNRISE" ] && [ "$NOW" -lt "$MORNING_END" ]; then
    TOD="morning"
elif [ "$NOW" -ge "$MORNING_END" ] && [ "$NOW" -lt "$DAY_END" ]; then
    TOD="day"
elif [ "$NOW" -ge "$DAY_END" ] && [ "$NOW" -lt "$LUNCH_END" ]; then
    TOD="lunch"
elif [ "$NOW" -ge "$LUNCH_END" ] && [ "$NOW" -lt "$AFTERNOON_END" ]; then
    TOD="afternoon"
elif [ "$NOW" -ge "$AFTERNOON_END" ] && [ "$NOW" -lt "$EVENING_END" ]; then
    TOD="evening"
else
    TOD="night"
fi

# === PICK IMAGE BASED ON CONDITION + TIME ===
IMAGE="$WALLPAPER_DIR/${TOD}_clear.jpg"

if [[ "$CONDITION" == *"rain"* ]]; then
    IMAGE="$WALLPAPER_DIR/${TOD}_rain.jpg"
elif [[ "$CONDITION" == *"cloud"* ]] || [ "$CLOUDS" -gt 80 ]; then
    IMAGE="$WALLPAPER_DIR/${TOD}_clouds.jpg"
fi

# === CLEAN UP OLD WALLPAPER ===
for FILE in "$OUTPUT"_*.jpg; do
    [ -f "$FILE" ] && rm "$FILE" && echo "[$(date)] Removed old wallpaper: $FILE" >> "$LOG_PATH"
done

# === COPY TO CONSISTENT FILE ===
TIMESTAMP="$NOW"
OUTPUT_FILE="$OUTPUT"_"$TIMESTAMP".jpg
cp "$IMAGE" "$OUTPUT_FILE"

# === CHANGE WALLPAPER ===
osascript <<EOF
tell application "System Events"
    repeat with d in desktops
        set picture of d to "$OUTPUT_FILE"
    end repeat
end tell
EOF

# === LOG CURRENT STATUS ===
echo "[$(date)] Attempted wallpaper change" >> "$LOG_PATH"
echo "[$(date)] Condition: $CONDITION | TOD: $TOD | Wallpaper: $IMAGE" >> "$LOG_PATH"
