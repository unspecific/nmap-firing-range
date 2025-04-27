#!/bin/sh

# Print content type header
echo "Content-type: text/plain"
echo ""

# Read form data from stdin (POST)
read QUERY_STRING

# Function to decode URL encoded string
urldecode() {
  local url_encoded="${1//+/ }"
  printf '%b' "${url_encoded//%/\\x}"
}

# Function to parse query string and extract values
get_value() {
  local param=$1
  local value=$(echo "$QUERY_STRING" | grep -oE "(^|&)$param=[^&]+" | sed "s/^&$param=//;s/^$param=//")
  urldecode "$value"
}

# Get session ID from environment
SESSION_ID="$SESSION_ID"
LAB_DIR="/opt/firing-range"
LOG_DIR="logs"
SESSION_DIR="$LAB_DIR/$LOG_DIR/lab_$SESSION_ID"
SCORE_CARD="$SESSION_DIR/score_card"
SCORE_FILE="$SESSION_DIR/score.json"
GROUND_TRUTH="$SESSION_DIR/mapping.txt"

# Extract values from query string
USERNAME=$(get_value "username")
HOSTNAME=$(get_value "hostname")
SERVICE=$(get_value "service")
TARGET=$(get_value "target")
PORT=$(get_value "port")
PROTO=$(get_value "proto")
FLAG=$(get_value "flag")
ACTION=$(get_value "action")

# Validate required fields
if [ -z "$TARGET" ]; then
  echo "error: Missing IP address"
  exit 1
fi

# Initialize score file if it doesn't exist
if [ ! -f "$SCORE_FILE" ]; then
  echo '{"username":"","score":0,"attempts":0}' > "$SCORE_FILE"
fi

# Handle different actions
case "$ACTION" in
  "delete")
    # Delete entry matching the IP address
    sed -i "/target=$TARGET/d" "$SCORE_CARD"
    echo "success: Entry deleted"
    ;;
    
  "reset")
    # Reset score card and score
    echo "# 🎩 Nmap Firing Range ScoreCard
session=$SESSION_ID" > "$SCORE_CARD"
    echo '{"username":"","score":0,"attempts":0}' > "$SCORE_FILE"
    echo "success: Score card reset"
    ;;
    
  "save_name")
    if [ -z "$USERNAME" ]; then
      echo "error: Username required"
      exit 1
    fi
    # Update username in score file
    sed -i "s/\"username\":\"[^\"]*\"/\"username\":\"$USERNAME\"/" "$SCORE_FILE"
    echo "success: Username saved"
    ;;
    
  *)
    # Validate required fields for submission
    if [ -z "$HOSTNAME" ] || [ -z "$SERVICE" ] || [ -z "$PORT" ] || [ -z "$PROTO" ] || [ -z "$FLAG" ]; then
      echo "error: Missing required fields"
      exit 1
    fi
    
    # Check if entry exists
    EXISTING=$(grep "target=$TARGET" "$SCORE_CARD")
    
    # Get current score data
    SCORE_DATA=$(cat "$SCORE_FILE")
    CURRENT_SCORE=$(echo "$SCORE_DATA" | sed 's/.*"score":\([0-9]*\).*/\1/')
    ATTEMPTS=$(echo "$SCORE_DATA" | sed 's/.*"attempts":\([0-9]*\).*/\1/')
    
    # Verify against ground truth
    TRUTH_ENTRY=$(grep "IP=$TARGET" "$GROUND_TRUTH")
    if [ -n "$TRUTH_ENTRY" ]; then
      CORRECT=0
      echo "$TRUTH_ENTRY" | while IFS= read -r line; do
        if echo "$line" | grep -q "Hostname=$HOSTNAME" && \
           echo "$line" | grep -q "Port=$PORT" && \
           echo "$line" | grep -q "Proto=$PROTO" && \
           echo "$line" | grep -q "Flag=$FLAG"; then
          CORRECT=$((CORRECT + 1))
        fi
      done
      
      # Update score
      if [ "$CORRECT" -gt 0 ]; then
        NEW_SCORE=$((CURRENT_SCORE + CORRECT))
        # Bonus for all correct on first try
        if [ -z "$EXISTING" ] && [ "$CORRECT" -eq 5 ]; then
          NEW_SCORE=$((NEW_SCORE + 5))
        fi
      else
        # Penalty for wrong submission
        NEW_SCORE=$((CURRENT_SCORE - 1))
        if [ "$NEW_SCORE" -lt 0 ]; then
          NEW_SCORE=0
        fi
      fi
      
      # Update score file
      ATTEMPTS=$((ATTEMPTS + 1))
      sed -i "s/\"score\":[0-9]*/\"score\":$NEW_SCORE/" "$SCORE_FILE"
      sed -i "s/\"attempts\":[0-9]*/\"attempts\":$ATTEMPTS/" "$SCORE_FILE"
      
      # Update or add entry
      if [ -n "$EXISTING" ]; then
        sed -i "s/.*target=$TARGET.*/hostname=$HOSTNAME service=$SERVICE target=$TARGET port=$PORT proto=$PROTO flag=$FLAG/" "$SCORE_CARD"
      else
        echo "hostname=$HOSTNAME service=$SERVICE target=$TARGET port=$PORT proto=$PROTO flag=$FLAG" >> "$SCORE_CARD"
      fi
      
      echo "success: Score card updated (Score: $NEW_SCORE)"
    else
      echo "error: Invalid IP address"
    fi
    ;;
esac