#!/bin/sh

# Print content type header
echo "Content-type: application/json"
echo ""

# Get session ID from environment
SESSION_ID="$SESSION_ID"
LAB_DIR="/opt/firing-range"
LOG_DIR="logs"
SESSION_DIR="$LAB_DIR/$LOG_DIR/lab_$SESSION_ID"
SCORE_FILE="$SESSION_DIR/score.json"

# Return score data
if [ -f "$SCORE_FILE" ]; then
  cat "$SCORE_FILE"
else
  echo '{"username":"","score":0,"attempts":0}'
fi