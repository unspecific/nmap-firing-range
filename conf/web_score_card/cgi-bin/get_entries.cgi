#!/bin/sh

# Print content type header
echo "Content-type: text/plain"
echo ""

# Get session ID from environment
SESSION_ID="$SESSION_ID"
LAB_DIR="/opt/firing-range"
LOG_DIR="logs"
SESSION_DIR="$LAB_DIR/$LOG_DIR/lab_$SESSION_ID"
SCORE_CARD="$SESSION_DIR/score_card"

# Check if score card exists
if [ -f "$SCORE_CARD" ]; then
  # Skip header line and output the rest
  tail -n +2 "$SCORE_CARD"
else
  echo "error: Score card not found"
fi