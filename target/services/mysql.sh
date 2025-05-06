#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# ─── Emulator Metadata ─────────────────────────────────────────────────────
EM_PORT="tcp:3306"             # MySQL classic port
EM_VERSION="8.0.27"            # Fake version
EM_DAEMON="FakeMySQLd"
EM_DESC="MySQL emulator with simple SQL and flag table"

# Credentials
CORRECT_USER="${USERNAME:-root}"
CORRECT_PASS="${PASSWORD:-toor}"
AUTHENTICATED=false

# Session state
CURRENT_DB=""

# Send a fake handshake banner
echo "Welcome to $EM_DAEMON (MySQL $EM_VERSION)!"

# Simple auth: expect "AUTH <user> <pass>"
while read -r line; do
  read -r cmd user pass <<<"$line"
  if [[ "${cmd^^}" == "AUTH" ]]; then
    if [[ $user == "$CORRECT_USER" && $pass == "$CORRECT_PASS" ]]; then
      AUTHENTICATED=true
      echo "OK Authenticated as $user"
      break
    else
      echo "ERROR 1045 (28000): Access denied for user '$user'"
    fi
  else
    echo "ERROR: please authenticate with AUTH <user> <pass>"
  fi
done

# Main SQL loop
while read -r sql; do
  # strip trailing semicolon and whitespace
  stmt="${sql%%;}"
  stmt="${stmt#"${stmt%%[![:space:]]*}"}"
  stmt="${stmt%"${stmt##*[![:space:]]}"}"
  # uppercase for keyword matching
  upper="${stmt^^}"

  case "$upper" in
    "SHOW DATABASES")
      echo "information_schema"
      echo "mysql"
      echo "performance_schema"
      echo "flagdb"
      ;;
    "USE "*)
      db="${stmt#USE }"
      if [[ "${db,,}" == "flagdb" ]]; then
        CURRENT_DB="flagdb"
        echo "Database changed"
      else
        echo "ERROR 1049 (42000): Unknown database '$db'"
      fi
      ;;
    "SHOW TABLES")
      if [[ $CURRENT_DB == "flagdb" ]]; then
        echo "tbl_flag"
      else
        echo "ERROR 1046 (3D000): No database selected"
      fi
      ;;
    "SELECT FLAG FROM TBL_FLAG")
      if [[ $CURRENT_DB == "flagdb" ]]; then
        echo "$FLAG"
      else
        echo "ERROR 1046 (3D000): No database selected"
      fi
      ;;
    "SELECT @@VERSION")
      echo "$EM_VERSION"
      ;;
    QUIT|EXIT)
      echo "Bye"
      break
      ;;
    *)
      echo "ERROR 1064 (42000): You have an error in your SQL syntax near '$stmt'"
      ;;
  esac
done

# allow scanners to grab last lines
sleep 1
