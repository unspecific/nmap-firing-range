#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# ─── Emulator Metadata ─────────────────────────────────────────────────────
EM_PORT="tcp:8080 tcp:8443:tls"
EM_VERSION="1.5"
EM_DAEMON="FakeAPI"
EM_DESC="HTTP REST API, fake flags"

HOST=$(hostname)
SERVER_HDR="$EM_DAEMON/$EM_VERSION"

# Real flag (injected via env)
REAL_FLAG="${FLAG:-flag{real-flag-here}}"
# Red herrings
FAKE1="flag{$(openssl rand -hex 3)}"
FAKE2="flag{$(openssl rand -hex 5)}"

SESSION_TOKEN=""

banner() {
  cat <<EOF
HTTP/1.1 200 OK
Server: $SERVER_HDR

{"message":"Welcome to $EM_DAEMON v$EM_VERSION on $HOST"}
EOF
}

# Read request line + headers + optional JSON body
read_request() {
  read -r request_line || return 1
  method=${request_line%% *}
  full_path=${request_line#* }; full_path=${full_path%% *}
  # Drop version
  # Collect headers
  headers=(); content_length=0; auth_header=""
  while IFS= read -r hdr && [[ -n "$hdr" ]]; do
    headers+=( "$hdr" )
    [[ $hdr =~ ^Content-Length:\ ([0-9]+) ]] && content_length=${BASH_REMATCH[1]}
    [[ $hdr =~ ^Authorization:\ (.+) ]]   && auth_header=${BASH_REMATCH[1]}
  done
  body=""
  if [[ $method =~ ^(POST|PUT)$ ]] && (( content_length > 0 )); then
    read -rn "$content_length" body
  fi
}

# Send JSON response
# args: status, body-json, [additional headers...]
send_json() {
  local status="$1"; shift
  local json="$1"; shift
  echo -e "HTTP/1.1 $status\r"
  echo -e "Server: $SERVER_HDR\r"
  echo -e "Content-Type: application/json\r"
  echo -e "Content-Length: ${#json}\r"
  for h in "$@"; do echo -e "$h\r"; done
  echo -e "\r"
  echo -e "$json\r"
}

# Very simple router
route() {
  case "$method $full_path" in
    "GET /api/flag")
      # require correct Bearer token
      if [[ $auth_header == "Bearer $SESSION_TOKEN" && -n $SESSION_TOKEN ]]; then
        send_json 200 "{\"flag\":\"$REAL_FLAG\"}"
      else
        send_json 401 "{\"error\":\"Unauthorized\"}"
      fi
      ;;
    "POST /api/login")
      # expect JSON: {"user":"...","pass":"..."}
      if [[ $body =~ \"user\"\ *:\ *\"([^"]+)\" ]] && [[ $body =~ \"pass\"\ *:\ *\"([^"]+)\" ]]; then
        user="${BASH_REMATCH[1]}"
        pass="${BASH_REMATCH[1]}"  # for demo assume pass==user
      else
        send_json 400 "{\"error\":\"Bad JSON\"}"
        return
      fi

      # very trivial auth
      if [[ $user == "${USERNAME:-admin}" && $pass == "${PASSWORD:-admin}" ]]; then
        SESSION_TOKEN="$(head /dev/urandom | tr -dc 'A-Za-z0-9' | head -c16)"
        send_json 200 "{\"status\":\"ok\",\"token\":\"$SESSION_TOKEN\"}"
      else
        send_json 403 "{\"status\":\"denied\"}"
      fi
      ;;
    "GET /api/users")
      send_json 200 '[{"id":1,"name":"alice"},{"id":2,"name":"bob"}]'
      ;;
    "GET /api/users/1")
      send_json 200 "{\"id\":1,\"name\":\"alice\",\"meta\":\"$FAKE1\"}"
      ;;
    "PUT /api/users/1")
      send_json 200 "{\"id\":1,\"name\":\"(updated)\",\"note\":\"nice try\"}"
      ;;
    "DELETE /api/users/1")
      send_json 200 "{\"status\":\"deleted\",\"flag\":\"$FAKE2\"}"
      ;;
    *)
      send_json 404 "{\"error\":\"Not found\"}"
      ;;
  esac
}

main() {
  banner
  while read_request; do
    route
  done
}

main
