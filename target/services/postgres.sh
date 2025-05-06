#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# ─── Emulator Metadata ─────────────────────────────────────────────────────
EM_PORT="tcp:5432 tcp:5433:tls"      # PostgreSQL ports
EM_VERSION="14.18"                  # Fake PostgreSQL version
EM_DAEMON="FakePostgreSQL"          # Daemon name
EM_DESC="PostgreSQL emulator, simple SQL interface"  # Short description

# Credentials and state
correct_user="${USERNAME:-}"
correct_pass="${PASSWORD:-}"
CURRENT_DB=""
AUTHENTICATED=false

# Send a welcome banner
echo "Welcome to $EM_DAEMON v$EM_VERSION on ${HOSTNAME:-localhost}"

echo "Please authenticate: AUTH <user> <pass>"
# Authentication loop
auth_loop() {
  while read -r line; do
    if [[ "$line" =~ ^AUTH[[:space:]]+([^[:space:]]+)[[:space:]]+(.+) ]]; then
      user="${BASH_REMATCH[1]}"
      pass="${BASH_REMATCH[2]}"
      if [[ "$user" == "$correct_user" && "$pass" == "$correct_pass" ]]; then
        AUTHENTICATED=true
        echo "OK Authenticated as $user"
        return 0
      else
        echo "ERROR: invalid credentials"
      fi
    else
      echo "ERROR: please authenticate with AUTH <user> <pass>"
    fi
  done
done

auth_loop
[[ "$AUTHENTICATED" != true ]] && exit 1

# SQL command loop
while read -r sql; do
  # Normalize spacing and case
  stmt="$(echo "$sql" | sed 's/[[:space:]]\+/ /g')"
  upper="$(echo "$stmt" | tr '[:lower:]' '[:upper:]')"

  case "$upper" in
    "SHOW SERVER_VERSION;"|"SELECT VERSION();")
      echo "$EM_VERSION"
      ;;
    "SHOW DATABASES;" )
      echo "postgres"
      echo "flagdb"
      ;;
    "USE flagdb;"|"SET DATABASE flagdb;")
      CURRENT_DB="flagdb"
      echo "Database changed to flagdb"
      ;;
    "SHOW TABLES;" )
      if [[ "$CURRENT_DB" == "flagdb" ]]; then
        echo "tbl_flag"
      else
        echo "ERROR: no database selected"
      fi
      ;;
    "SELECT FLAG FROM TBL_FLAG;" )
      if [[ "$CURRENT_DB" == "flagdb" ]]; then
        echo "$FLAG"
      else
        echo "ERROR: no database selected"
      fi
      ;;
    "QUIT"|"\\Q")
      echo "Goodbye"
      break
      ;;
    *)
      echo "ERROR: syntax error at \"$stmt\""
      ;;
  esac
done

# Delay so scanners capture output
sleep 1
