#!/bin/bash
EXE=$@

# Read the request line (e.g., "GET /api/flag HTTP/1.1")
read request
method=$(echo "$request" | awk '{print $1}')
path=$(echo "$request" | awk '{print $2}')

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
        body='{"flag": "flag{rest-get-works}"}'
        ;;
    "POST /api/login")
        body='{"status": "success", "token": "flag{fake-jwt-token}"}'
        ;;
    "DELETE /api/users/1")
        body='{"status": "user deleted", "flag": "flag{rest-delete-danger}"}'
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
