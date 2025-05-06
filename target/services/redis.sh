#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# ─── Emulator Metadata ─────────────────────────────────────────────────────
EM_PORT="tcp:6379 tcp:6380:tls"
EM_VERSION="6.6.6"
EM_DAEMON="FakeRedis"
EM_DESC="Redis emulator with flag in GET/KEYS"

HOST=$(hostname)
PASSWORD_VAR="${PASSWORD:-}"
AUTHENTICATED=false
declare -A STORE

REAL_FLAG="${FLAG:-flag{hidden-in-redis}}"
FLAG_KEY="flag"

# ─── RESP Helpers ───────────────────────────────────────────────────────────
send_simple_string()  { printf "+%s\r\n" "$1"; }
send_error()          { printf "-%s\r\n" "$1"; }
send_bulk_string()    { printf "$%s\r\n%s\r\n" "${#1}" "$1"; }
send_integer()        { printf ":%s\r\n" "$1"; }
send_nil()            { printf "$-1\r\n"; }
send_array() {
  local arr=("$@")
  printf "*%s\r\n" "${#arr[@]}"
  for elem in "${arr[@]}"; do send_bulk_string "$elem"; done
}

# ─── RESP Parser ────────────────────────────────────────────────────────────
# Reads one request (inline or RESP), sets: CMD, ARGS[]
parse_request() {
  ARGS=()
  read -r line || return 1
  if [[ $line == \** ]]; then
    # RESP array
    local n=${line#\*}
    for _ in $(seq 1 $n); do
      read -r size_line
      read -r content
      ARGS+=( "$content" )
    done
  else
    # inline
    ARGS=( $line )
  fi
  CMD="${ARGS[0]^^}"
}

# ─── Command Handlers ──────────────────────────────────────────────────────
cmd_auth() {
  local pass="${ARGS[1]:-}"
  if [[ -z "$PASSWORD_VAR" ]]; then
    send_error "ERR AUTH not enabled"
  elif [[ $pass == "$PASSWORD_VAR" ]]; then
    AUTHENTICATED=true
    send_simple_string "OK"
  else
    send_error "ERR invalid password"
  fi
}

cmd_ping() {
  send_simple_string "PONG"
}

cmd_info() {
  local info=$(
    cat <<EOF
# Server
redis_version:$EM_VERSION
# Clients
connected_clients:1
# Keyspace
db0:keys=${#STORE[@]},expires=0,avg_ttl=0
EOF
  )
  send_bulk_string "$info"
}

cmd_set() {
  local key="${ARGS[1]:-}" val="${ARGS[2]:-}"
  if [[ -z $key || -z $val ]]; then
    send_error "ERR wrong number of arguments for 'SET'"
  else
    STORE[$key]="$val"
    send_simple_string "OK"
  fi
}

cmd_get() {
  local key="${ARGS[1]:-}"
  if [[ $key == "$FLAG_KEY" ]]; then
    send_bulk_string "$REAL_FLAG"
  elif [[ -v STORE[$key] ]]; then
    send_bulk_string "${STORE[$key]}"
  else
    send_nil
  fi
}

cmd_flushall() {
  STORE=()
  send_simple_string "OK"
}

cmd_keys() {
  local pattern="${ARGS[1]:-\*}"
  local all_keys=("$FLAG_KEY" "${!STORE[@]}")
  local out=()
  for k in "${all_keys[@]}"; do
    if [[ $pattern == "*" || $k == $pattern ]]; then
      out+=( "$k" )
    fi
  done
  send_array "${out[@]}"
}

cmd_quit() {
  send_simple_string "OK"
  exit 0
}

# ─── Main Loop ──────────────────────────────────────────────────────────────
# Send initial banner
send_simple_string "$EM_DAEMON $EM_VERSION ready"

while parse_request; do
  # Enforce AUTH if set, except for AUTH/PING/QUIT
  if [[ -n "$PASSWORD_VAR" && $AUTHENTICATED == false ]] && [[ ! $CMD =~ ^(AUTH|PING|QUIT)$ ]]; then
    send_error "NOAUTH Authentication required."
    continue
  fi

  case $CMD in
    AUTH)      cmd_auth ;;
    PING)      cmd_ping ;;
    INFO)      cmd_info ;;
    SET)       cmd_set ;;
    GET)       cmd_get ;;
    FLUSHALL)  cmd_flushall ;;
    KEYS)      cmd_keys ;;
    QUIT)      cmd_quit ;;
    *)         send_error "ERR unknown command '$CMD'" ;;
  esac
done

# Give clients a moment to read the final lines
sleep 1
