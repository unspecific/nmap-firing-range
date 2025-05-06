#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# ─── Emulator Metadata ─────────────────────────────────────────────────────
EM_PORT="tcp:21 tcp:990:tls"
EM_VERSION="3.6"
EM_DAEMON="FakeFTPd"
EM_DESC="FTPd emulator, brute force required"

# Credentials & state
CORRECT_USER="${USERNAME:-}"
CORRECT_PASS="${PASSWORD:-}"
MAX_ATTEMPTS=5
attempts=0
authenticated=false

# Send the initial banner
banner() {
  echo -e "220-${EM_DAEMON}/${EM_VERSION} FTP server ready"
  echo -e "220-This is a fake FTPd emulator"
  echo -e "220-Use USER/PASS to log in, then LIST or RETR secret.txt"
  echo -e "220 End of banner"
}

# Handle login
auth_loop() {
  while (( attempts < MAX_ATTEMPTS )); do
    read -r line || exit 0
    cmd=${line%% *}; arg=${line#* }

    case "${cmd^^}" in
      USER)
        username="$arg"
        echo -e "331 Username ok, need password"
        ;;
      PASS)
        password="$arg"
        if [[ "$username" == "$CORRECT_USER" && "$password" == "$CORRECT_PASS" ]]; then
          echo -e "230 Login successful"
          authenticated=true
          return
        else
          ((attempts++))
          echo -e "530 Login incorrect (${attempts}/${MAX_ATTEMPTS})"
          if (( attempts >= MAX_ATTEMPTS )); then
            echo -e "421 Too many failed attempts – closing connection"
            exit 1
          fi
        fi
        ;;
      QUIT)
        echo -e "221 Goodbye"
        exit 0
        ;;
      *)
        echo -e "530 Please login with USER and PASS"
        ;;
    esac
  done
}

# Main FTP loop after auth
ftp_loop() {
  while read -r line || [[ -n "$line" ]]; do
    cmd=${line%% *}; arg=${line#* }

    case "${cmd^^}" in
      SYST)
        echo -e "215 UNIX Type: L8"
        ;;
      FEAT)
        echo -e "211-Features:"
        echo -e " EPRT"
        echo -e " EPSV"
        echo -e "211 End"
        ;;
      PASV)
        # stub—clients won’t actually open a data port
        echo -e "227 Entering Passive Mode (127,0,0,1,200,200)"
        ;;
      TYPE)
        echo -e "200 Type set to $arg"
        ;;
      LIST)
        echo -e "150 Here comes the directory listing"
        echo -e "-rw-r--r-- 1 owner group  42 $(date +'%b %d %Y') secret.txt"
        echo -e "226 Directory send OK"
        ;;
      RETR)
        if [[ "$arg" == "secret.txt" ]]; then
          echo -e "150 Opening BINARY mode data connection for $arg"
          echo -e "$FLAG"
          echo -e "226 Transfer complete"
        else
          echo -e "550 File not found"
        fi
        ;;
      QUIT)
        echo -e "221 Goodbye"
        exit 0
        ;;
      *)
        echo -e "502 Command not implemented"
        ;;
    esac
  done
}

main() {
  banner
  auth_loop
  ftp_loop
  # give scanners a moment to grab final output
  sleep 1
}

main
