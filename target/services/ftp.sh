#!/bin/bash

# ─── Emulator Metadata ─────────────────────────────────────────────────────
EM_PORT="tcp:21 tcp:990:tls"               # The port this service listens on
EM_VERSION="3.6"               # Optional version identifier
EM_DAEMON="FakeFTPd"
EM_DESC="FTPd emulator, brute force required"  # Short description for listing output


correct_user="$USERNAME"
correct_pass="$PASSWORD"
max_attempts=5
attempts=0
authenticated=false

echo -e "220 Welcome to $EM_DAEMON/$EM_VERSION"

while IFS= read -r line; do
    cmd=$(echo "$line" | awk '{print $1}')
    arg=$(echo "$line" | cut -d' ' -f2-)

  if [[ "$authenticted" != "true" ]]; then
    case "$cmd" in
      USER)
        username="$arg"
        echo "331 Username okay, need password."
        ;;
      PASS)
        password="$arg"
        if [[ "$username" == "$correct_user" && "$password" == "$correct_pass" ]]; then
          echo "230 Login successful."
          authenticated=true
          break
        else
          echo "530 Login incorrect."
          attempts=$((attempts + 1))
          if [[ "$attempts" -ge "$max_attempts" ]]; then
            echo "421 Too many failed attempts. Connection closed."
            exit 0
          fi
        fi
        ;;
      QUIT)
        echo "221 Goodbye."
        exit 0
        ;;
    esac
  else 
    case "$cmd" in
      LIST)
        echo "150 Opening ASCII mode data connection for file list."
        echo "-rw-r--r-- 1 root root 42 Apr 18 2025 secret.txt"
        echo "226 Transfer complete."
        ;;
      RETR)
        if [[ "$arg" == "secret.txt" ]]; then
          echo "150 Opening BINARY mode data connection for secret.txt"
          echo "$FLAG"
          echo "226 Transfer complete."
        else
          echo "550 File not found."
        fi
        ;;
      QUIT)
        echo "221 Goodbye."
        exit 0
        ;;
      *)
        echo "502 Command not implemented."
        ;;
    esac
  fi
done
sleep 1
