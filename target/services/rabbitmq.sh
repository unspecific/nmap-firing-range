#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# ─── Emulator Metadata ─────────────────────────────────────────────────────
EM_PORT="tcp:15672 tcp:15671:tls"       # Management HTTP API ports
EM_VERSION="3.8.0"                     # Fake RabbitMQ version
EM_DAEMON="FakeRabbitMQ"                # Daemon name
EM_DESC="RabbitMQ Management API emulator"

HOST=$(hostname)
USERNAME_ENV="${USERNAME:-guest}"
PASSWORD_ENV="${PASSWORD:-guest}"
FLAG="${FLAG:-flag{rabbitmq-management}}"

# Helper to send HTTP responses
send_response() {
  local status_line="$1" body="$2" content_type="${3:-application/json}"
  echo -e "HTTP/1.1 $status_line\r"
  echo -e "Server: $EM_DAEMON/$EM_VERSION\r"
  echo -e "Content-Type: $content_type; charset=utf-8\r"
  echo -e "Content-Length: ${#body}\r"
  echo -e "Connection: close\r"
  echo -e "\r"
  echo -e "$body"
}

# Read the request line
IFS= read -r request_line || exit 0
method=$(awk '{print $1}' <<<"$request_line")
uri=$(awk '{print $2}' <<<"$request_line")

# Read and parse headers
declare -A headers
while IFS= read -r header && [[ -n "$header" ]]; do
  key=${header%%:*}
  val=${header#*: }
  headers["$key"]="$val"
done

# Basic auth enforcement
expected_auth="Basic $(echo -n "$USERNAME_ENV:$PASSWORD_ENV" | base64)"
if [[ "${headers[Authorization]:-}" != "$expected_auth" ]]; then
  body='{"error":"Unauthorized"}'
  send_response "401 Unauthorized" "$body"
  exit 0
fi

# Route the request
case "$method $uri" in
  "GET /api/overview")
    body='{"management_version":"'$EM_VERSION'","rabbitmq_version":"'$EM_VERSION'"}'
    send_response "200 OK" "$body"
    ;;

  "GET /api/queues")
    # List all queues, including our flag queue
    body='[{"vhost":"/","name":"flag_queue","messages":1}]'
    send_response "200 OK" "$body"
    ;;

  "DELETE /api/queues/%2F/flag_queue/contents")
    # Clear queue contents placeholder
    body='{"message_count":1}'
    send_response "200 OK" "$body"
    ;;

  "POST /api/queues/%2F/flag_queue/get")
    # Simulate fetching the message (flag)
    body='[{"payload":"'$FLAG'","payload_bytes":'${#FLAG}'}]'
    send_response "200 OK" "$body"
    ;;

  *)
    body='{"error":"Not Found"}'
    send_response "404 Not Found" "$body"
    ;;
esac

# brief pause to allow clients to read
echo "" && sleep 1
