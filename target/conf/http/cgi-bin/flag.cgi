#!/usr/bin/env sh
# fetch_flag.cgi — gatekeeper: serves flag only when correct token is present,
# otherwise returns a 404 and your custom err404.html page.

# Base directory where thttpd serves files
HTTP_DIR="/opt/target/conf/http"
ERROR_PAGE="$HTTP_DIR/errors/err404.html"
FLAG_FILE="$HTTP_DIR/.flag"

# Decode the expected token (base64 of “FiringRange”)
EXPECTED_TOKEN=$(printf 'RmlyZ2luZ1Jhbmdl' | base64 -d)

# CGI exposes “X-FR-Token” as HTTP_X_FR_TOKEN
if [ "$HTTP_X_FR_TOKEN" = "$EXPECTED_TOKEN" ]; then
  # Correct token: return the flag
  printf 'Content-Type: text/plain; charset=utf-8\r\n'
  printf '\r\n'
  cat "$FLAG_FILE"
  exit 0
else
  # Wrong or missing token: return 404 plus your custom error page
  printf 'Status: 404\r\n'
  printf 'Content-Type: text/html; charset=UTF-8\r\n'
  printf '\r\n'
  cat "$ERROR_PAGE"
  exit 0
fi
