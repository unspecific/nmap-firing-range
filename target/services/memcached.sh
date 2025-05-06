#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# ─── Emulator Metadata ─────────────────────────────────────────────────────
EM_PORT="tcp:11211"
EM_VERSION="6.1"
EM_DAEMON="memfaked"
EM_DESC="Memcached emulator with full ASCII protocol"

# Session state
declare -A STORE FLAGS
START_TIME=$(date +%s)
TOTAL_ITEMS=0
TOTAL_BYTES=0

# Preload the flag
FLAG_KEY="flag"
FLAG_VALUE="${FLAG:-flag{hidden-in-memcached}}"
STORE[$FLAG_KEY]="$FLAG_VALUE"
FLAGS[$FLAG_KEY]=0
TOTAL_ITEMS=1
TOTAL_BYTES=${#FLAG_VALUE}

# Helpers
send()   { printf "%s\r\n" "$*"; }
uptime() { echo $(( $(date +%s) - START_TIME )); }

handle_version() {
  send "VERSION $EM_VERSION-$EM_DAEMON"
}

handle_stats() {
  send "STAT pid $$"
  send "STAT uptime $(uptime)"
  send "STAT version $EM_VERSION"
  send "STAT curr_items ${#STORE[@]}"
  send "STAT total_items $TOTAL_ITEMS"
  send "STAT bytes $TOTAL_BYTES"
  send "END"
}

handle_get() {
  for key in "$@"; do
    if [[ -v STORE[$key] ]]; then
      local flags=${FLAGS[$key]}
      local data=${STORE[$key]}
      local bytes=${#data}
      send "VALUE $key $flags $bytes"
      send "$data"
    fi
  done
  send "END"
}

handle_set() {
  local key=$1 flags=$2 exptime=$3 bytes=$4
  # Read the next line of data
  IFS= read -r data
  STORE[$key]="$data"
  FLAGS[$key]="$flags"
  (( TOTAL_ITEMS++ ))
  (( TOTAL_BYTES += ${#data} ))
  send "STORED"
}

handle_delete() {
  local key=$1
  if [[ -v STORE[$key] ]]; then
    unset STORE[$key] FLAGS[$key]
    send "DELETED"
  else
    send "NOT_FOUND"
  fi
}

handle_incr() {
  local key=$1 delta=$2
  if [[ -v STORE[$key] ]]; then
    local val=${STORE[$key]}
    if [[ $val =~ ^[0-9]+$ ]]; then
      val=$(( val + delta ))
      STORE[$key]=$val
      send "$val"
    else
      send "CLIENT_ERROR cannot increment non-numeric value"
    fi
  else
    send "NOT_FOUND"
  fi
}

handle_decr() {
  local key=$1 delta=$2
  if [[ -v STORE[$key] ]]; then
    local val=${STORE[$key]}
    if [[ $val =~ ^[0-9]+$ ]]; then
      val=$(( val - delta ))
      (( val < 0 )) && val=0
      STORE[$key]=$val
      send "$val"
    else
      send "CLIENT_ERROR cannot decrement non-numeric value"
    fi
  else
    send "NOT_FOUND"
  fi
}

handle_flush_all() {
  STORE=(); FLAGS=()
  TOTAL_ITEMS=0; TOTAL_BYTES=0
  send "OK"
}

# Main loop
handle_version
while IFS= read -r line; do
  # Split into tokens
  read -ra toks <<< "$line"
  cmd=${toks[0],,}
  args=("${toks[@]:1}")

  case "$cmd" in
    version)    handle_version ;;
    stats)      handle_stats ;;
    get)        handle_get "${args[@]}" ;;
    set)        handle_set "${args[@]}" ;;
    delete)     handle_delete "${args[0]}" ;;
    incr)       handle_incr "${args[0]}" "${args[1]:-1}" ;;
    decr)       handle_decr "${args[0]}" "${args[1]:-1}" ;;
    flush_all)  handle_flush_all ;;
    quit|exit)  send "OK"; break ;;
    *)          send "ERROR" ;;
  esac
done

# give clients a moment to grab the last lines
sleep 1
