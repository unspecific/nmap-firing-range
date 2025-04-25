#!/bin/bash
EXE=$@

# ─── Emulator Metadata ─────────────────────────────────────────────────────
EM_PORT="8080 8443:tls"               # The port this service listens on
EM_VERSION="1.5"               # Optional version identifier
EM_DESC="HTTP REST API interface"  # Short description for listing output
EM_DAEMON="FakeAPI"

# Read the request line (e.g., "GET /api/flag HTTP/1.1")
read request
method=$(echo "$request" | awk '{print $1}')
path=$(echo "$request" | awk '{print $2}')

FAKE1=$(echo "FLAG{$(openssl rand -hex 3)}-")
FAKE2=$(echo "FLAG{$(openssl rand -hex 12)}-")

# Read and discard headers
while read header && [ "$header" != $'\r' ]; do
    :
done

# Default response values
status_code="200 OK"
content_type="application/json"
body='{"message": "Default response"}'

# Handle REST paths
case "$method $path" in
    "GET /api/flag")
        body="{\"flag\": \"$FLAG\"}"
        ;;
    "POST /api/login")
        body="{\"status\": \"success\", \"token\": \"$FAKE1\"}"
        ;;
    "DELETE /api/users/1")
        body="{\"status\": \"user deleted\", \"flag\": \"$FAKE2\"}"
        ;;
    "PUT /api/users/1")
        body='{"status": "user updated", "info": "Nice try."}'
        ;;
    *)
        status_code="404 Not Found"
        body='{"error": "Not found"}'
        ;;
esac

# Return HTTP response
echo -e "HTTP/1.1 $status_code\r"
echo -e "Content-Type: $content_type\r"
echo -e "Content-Length: ${#body}\r"
echo -e "Connection: close\r"
echo -e "\r"
echo -e "$body\r"
