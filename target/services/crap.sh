#!/bin/bash

# Function to process input and return response
get_response() {
    local input="$1"
    local clean="${input%%$'\r'}"  # Strip trailing carriage return if present

    # Split into command and argument
    local cmd=$(echo "$clean" | awk '{print toupper($1)}')
    local arg=$(echo "$clean" | cut -d' ' -f2-)

    case "$cmd" in
        HELLO)
            echo "200 Hello, $arg $clean"
            ;;
        FLAG)
            echo "200 flag{example-response}"
            ;;
        QUIT)
            echo "221 Goodbye."
            exit 0
            ;;
        *)
            echo "500 Unknown command: $cmd"
            ;;
    esac
}

# Optional startup banner
echo "220 Fake Protocol Service Ready"

# Main read loop
while IFS= read -r line || [[ -n "$line" ]]; do
    get_response "$line"
done

# Optional cleanup
echo "[DEBUG] Client disconnected"
sleep 1
