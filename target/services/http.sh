#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# ─── Emulator Metadata ─────────────────────────────────────────────────────
EM_PORT="tcp:80 tcp:443:tls"
EM_VERSION="1.1"
EM_DAEMON="FakeHTTPd"
EM_DESC="HTTP/web server with login flow"

# Configurable
HOST=$(hostname)
SERVER_HDR="$EM_DAEMON/$EM_VERSION"
CORRECT_USER="${USERNAME:-user}"
CORRECT_PASS="${PASSWORD:-pass}"
SESSION_ID=""
COOKIE_NAME="session"

# Read one request (line + headers + optional body)
read_request() {
  read -r request_line || return 1
  request_line="${request_line%%$'\r'}"
  method=${request_line%% *}
  path=${request_line#* }; path=${path%% *}

  headers=(); content_length=0; authorization=""; cookie=""
  while IFS= read -r line && [[ -n "$line" ]]; do
    headers+=( "$line" )
    [[ $line =~ ^Content-Length:\ ([0-9]+) ]] && content_length=${BASH_REMATCH[1]}
    [[ $line =~ ^Cookie:\ (.*) ]]      && cookie=${BASH_REMATCH[1]}
  done

  body=""
  if [[ $method == "POST" && $content_length -gt 0 ]]; then
    read -rn $content_length body
    body="${body%%$'\r'}"
  fi
}

# Send response: status, headers array, body
send_response() {
  local status="$1"; shift
  local hdrs=("$@") 
  echo -e "HTTP/1.1 $status\r"
  printf "Server: %s\r\n" "$SERVER_HDR"
  for h in "${hdrs[@]}"; do printf "%s\r\n" "$h"; done
  echo -e "\r"
  echo -e "${RESP_BODY}\r"
}

# URL-encode payloads simply (spaces->+)
url_decode() {
  echo -e "${1//+/ }" | sed 's/%\([0-9A-F][0-9A-F]\)/\\x\1/g' | xargs -0 printf "%b"
}

# Handlers
handle_root() {
  RESP_BODY=$(
    cat <<HTML
<html>
  <head><title>Welcome</title></head>
  <body>
    <h1>Welcome to FakeHTTPd!</h1>
    <p><a href="/login">Login to continue</a></p>
  </body>
</html>
HTML
  )
  send_response "200 OK" "Content-Type: text/html; charset=utf-8" "Content-Length: ${#RESP_BODY}"
}

handle_login_get() {
  RESP_BODY=$(
    cat <<'HTML'
<html>
  <head><title>Login</title></head>
  <body>
    <h2>Please log in</h2>
    <form method="POST" action="/login">
      User: <input name="username"><br>
      Pass: <input name="password" type="password"><br>
      <button>Login</button>
    </form>
  </body>
</html>
HTML
  )
  send_response "200 OK" "Content-Type: text/html; charset=utf-8" "Content-Length: ${#RESP_BODY}"
}

handle_login_post() {
  # body: username=foo&password=bar
  IFS='&' read -r u p <<< "$body"
  user=$(url_decode "${u#username=}")
  pass=$(url_decode "${p#password=}")

  if [[ $user == "$CORRECT_USER" && $pass == "$CORRECT_PASS" ]]; then
    SESSION_ID=$(head /dev/urandom | tr -dc 'a-f0-9' | head -c16)
    # Set cookie and redirect
    send_response "302 Found" \
      "Set-Cookie: ${COOKIE_NAME}=${SESSION_ID}; HttpOnly" \
      "Location: /dashboard"
  else
    RESP_BODY='{"status":"error","message":"Invalid credentials"}'
    send_response "401 Unauthorized" \
      "Content-Type: application/json" \
      "Content-Length: ${#RESP_BODY}"
  fi
}

handle_dashboard() {
  # require correct cookie
  if [[ $cookie == "${COOKIE_NAME}=${SESSION_ID}" ]]; then
    RESP_BODY=$(
      cat <<JSON
{"message":"Welcome, $CORRECT_USER","endpoints":["/flag","/api/info"]}
JSON
    )
    send_response "200 OK" "Content-Type: application/json" "Content-Length: ${#RESP_BODY}"
  else
    send_response "403 Forbidden" "Content-Type: text/plain" "Content-Length: 9"
    RESP_BODY="Forbidden"
  fi
}

handle_flag() {
  if [[ $cookie == "${COOKIE_NAME}=${SESSION_ID}" ]]; then
    RESP_BODY="{\"flag\":\"$FLAG\"}"
    send_response "200 OK" "Content-Type: application/json" "Content-Length: ${#RESP_BODY}"
  else
    send_response "403 Forbidden" "Content-Type: text/plain" "Content-Length: 9"
    RESP_BODY="Forbidden"
  fi
}

handle_api_info() {
  RESP_BODY=$(
    cat <<JSON
{"server":"$SERVER_HDR","time":"$(date -u +%Y-%m-%dT%H:%M:%SZ)","session":"$SESSION_ID"}
JSON
  )
  send_response "200 OK" "Content-Type: application/json" "Content-Length: ${#RESP_BODY}"
}

handle_404() {
  RESP_BODY='{"error":"Not Found"}'
  send_response "404 Not Found" "Content-Type: application/json" "Content-Length: ${#RESP_BODY}"
}

# Main
read_request || exit
case "$method $path" in
  "GET /")          handle_root ;;
  "GET /login")     handle_login_get ;;
  "POST /login")    handle_login_post ;;
  "GET /dashboard") handle_dashboard ;;
  "GET /flag")      handle_flag ;;
  "GET /api/info")  handle_api_info ;;
  *)                 handle_404 ;;
esac

# allow scanners to grab the end
sleep 1
