#!/bin/bash

# Stream live log updates using Server-Sent Events (SSE)
LOG_FILE="/var/log/containers"  # <-- set your correct log file here


echo "Content-Type: text/event-stream"
echo "Cache-Control: no-cache"
echo ""

if [[ -z "$LOG_FILE" ]]; then
    echo "No log file found"
else
  # Tail and send new lines
  tail -n 10 -f "$LOG_FILE" 2>/dev/null | while read -r line
  do
    echo "data: $line"
    echo
    sleep 0.1
  done
fi
