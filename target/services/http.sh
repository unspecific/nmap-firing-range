#!/bin/bash

# Function to handle an HTTP request line
get_response() {
    export LC_ALL=C 
    local request="$1"
    local method=$(echo "$request" | awk '{print toupper($1)}')
    local path=$(echo "$request" | awk '{print $2}')

    # Default response
    local status="200 OK"
    local body='{"message": "default response"}'

    case "$method $path" in
        "GET /")
            body='{"message": "Welcome to the fake API"}'
            ;;
        "GET /flag")
            body='{"flag": "flag{http-line-parser-win}"}'
            ;;
        "POST /login")
            body='{"status": "login failed"}'
            ;;
        *)
            status="404 Not Found"
            body='{"error": "Not found"}'
            ;;
    esac

    echo -e "HTTP/1.1 $status\r"
    echo -e "Content-Type: application/json\r"
    echo -e "Content-Length: ${#body}\r"
    echo -e "Connection: close\r"
    echo -e "\r"
    echo -e "$body\r"
}

# Read the request line
IFS= read -r request_line || exit 0
request_line="${request_line%%$'\r'}"  # Strip \r if client used CRLF

# Read and discard headers
while IFS= read -r header && [[ -n "$header" ]]; do
    :
done

# Call the response generator
get_response "$request_line"

# Hold briefly to avoid broken pipe
# sleep 1
