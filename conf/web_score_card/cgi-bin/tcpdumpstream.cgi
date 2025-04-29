#!/bin/bash
logger "Launching TCPDump streammer"

LOG_FILE="/var/log/tcpdump.log"

echo "Content-Type: text/event-stream"
echo "Cache-Control: no-cache"
echo ""

# Safe fallback
[ ! -f "$LOG_FILE" ] && touch "$LOG_FILE"

# When client disconnects, kill everything
trap "exit 0" SIGPIPE

# Tail and stream
tail -n 100 -F "$LOG_FILE" 2>/dev/null | while read -r line; do
    datetime=$(echo "$line" | awk '{print $1}')
    interface=$(echo "$line" | awk '{print $2}')
    direction=$(echo "$line" | awk '{print $3}')
    proto=$(echo "$line" | awk '{print $4}')
    src=$(echo "$line" | awk '{print $5}')
    dst=$(echo "$line" | awk '{print $7}' | sed 's/://')

    [ -z "$dst" ] && continue

    echo "data: $datetime|$interface|$direction|$proto|$src|$dst"
    echo
    sleep 0.05 || break  # Important: break if writing fails
done
