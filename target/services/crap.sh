#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# ─── Emulator Metadata ─────────────────────────────────────────────────────
EM_PORT="tcp:9999 tcp:9443:tls"
EM_VERSION="32.1"
EM_DAEMON="Unspecific"
EM_DESC="Custom API for proprietary client"

# ANSI colors
BOLD=$'\e[1m'; CYAN=$'\e[36m'; YELLOW=$'\e[33m'; RED=$'\e[31m'; RESET=$'\e[0m'

# Session state
SESSION_ID=$(head /dev/urandom | tr -dc 'A-F0-9' | head -c8)
CHALLENGE_ANSWER=
SOLVED=false
FLAG_CONTENT="${FLAG:-flag{override-via-env}}"

banner() {
  printf "%b" "${CYAN}${BOLD}"
  cat <<'EOF'
  _   _                _       ____        _   
 | | | | ___  __ _  __| | ___ |  _ \  ___ | |_ 
 | |_| |/ _ \/ _` |/ _` |/ _ \| | | |/ _ \| __|
 |  _  |  __/ (_| | (_| | (_) | |_| | (_) | |_ 
 |_| |_|\___|\__,_|\__,_|\___/|____/ \___/ \__|
EOF
  printf "%b\n" "${RESET}"
  echo "220-$EM_DAEMON/$EM_VERSION Ready"
  echo "220-Session: $SESSION_ID"
  echo "220 PROTOCOL v1.0"
}

gen_challenge() {
  local a=$(( RANDOM % 20 + 1 ))
  local b=$(( RANDOM % 20 + 1 ))
  CHALLENGE_ANSWER=$(( a + b ))
  echo "{\"challenge\": \"What is $a + $b ?\"}"
}

get_response() {
  local raw="${1//$'\r'/}"
  local cmd="${raw%% *}"
  local arg="${raw#* }"

  case "${cmd^^}" in
    HELLO)
      # Greet and echo session
      echo "{\"code\":200, \"msg\":\"Hello! Session $SESSION_ID\"}"
      ;;
    CHALLENGE)
      # Send a JSON‐like math challenge
      echo "{\"code\":250, \"body\": $(gen_challenge)}"
      ;;
    ANSWER)
      # Check the previously generated challenge
      if [[ "$arg" -eq "$CHALLENGE_ANSWER" ]]; then
        SOLVED=true
        echo "{\"code\":250, \"msg\":\"Correct! You may now request FLAG.\"}"
      else
        echo "{\"code\":550, \"msg\":\"Wrong answer.\"}"
      fi
      ;;
    FLAG)
      if $SOLVED; then
        echo "{\"code\":250, \"flag\":\"$FLAG_CONTENT\"}"
      else
        echo "{\"code\":550, \"msg\":\"No flag until you solve the challenge.\"}"
      fi
      ;;
    TIME)
      echo "{\"code\":200, \"time\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}"
      ;;
    ECHO)
      echo "{\"code\":200, \"echo\":\"$arg\"}"
      ;;
    HELP)
      echo '{"code":214, "supported":["HELLO","CHALLENGE","ANSWER <n>","FLAG","TIME","ECHO <text>","QUIT"]}'
      ;;
    QUIT)
      echo "{\"code\":221, \"msg\":\"Goodbye.\"}"
      exit 0
      ;;
    *)
      echo "{\"code\":500, \"error\":\"Unknown command: $cmd\"}"
      ;;
  esac
}

main() {
  banner
  # Read loop (handles last line without newline)
  while IFS= read -r line || [[ -n "$line" ]]; do
    get_response "$line"
  done
  echo "[DEBUG] Client disconnected"
  sleep 1
}

main
