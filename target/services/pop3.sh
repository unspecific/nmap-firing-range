#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# ─── Emulator Metadata ─────────────────────────────────────────────────────
EM_PORT="tcp:110 tcp:995:tls"
EM_VERSION="9.72.12"
EM_DAEMON="FakePOP3d"
EM_DESC="POP3 with brute force enabled"

# ANSI colors
BOLD=$'\e[1m'; CYAN=$'\e[36m'; GREEN=$'\e[32m'; RED=$'\e[31m'; RESET=$'\e[0m'

# Derived
HOST=$(hostname)
USERVAR="${USERNAME:-}"
PASSVAR="${PASSWORD:-}"
MAX_ATTEMPTS=5

banner() {
  printf "%b" "${CYAN}${BOLD}"
  echo "========================================"
  printf "   %s v%s\n" "$EM_DAEMON" "$EM_VERSION"
  echo "========================================"
  printf "%b\n" "${RESET}"
  echo -e "+OK $EM_DAEMON/$EM_VERSION server ready <root@$HOST>\r"
}

auth_loop() {
  local attempts=0
  while (( attempts < MAX_ATTEMPTS )); do
    # expect: USER <name>
    IFS= read -r line
    if [[ "${line^^}" =~ ^USER[[:space:]]+(.+) ]]; then
      local try_user=${BASH_REMATCH[1]}
      echo -e "+OK User accepted\r"
    else
      echo -e "-ERR Send USER first\r"
      continue
    fi

    # expect: PASS <pass>
    IFS= read -r line
    if [[ "${line^^}" =~ ^PASS[[:space:]]+(.+) ]]; then
      local try_pass=${BASH_REMATCH[1]}
    else
      echo -e "-ERR Send PASS next\r"
      continue
    fi

    if [[ $try_user == "$USERVAR" && $try_pass == "$PASSVAR" ]]; then
      echo -e "+OK Authenticated\r"
      return 0
    else
      (( attempts++ ))
      echo -e "-ERR Authentication failed (${attempts}/${MAX_ATTEMPTS})\r"
    fi
  done

  echo -e "-ERR Too many failures – closing\r"
  sleep 1
  exit 1
}

pop3_loop() {
  local mailbox_size=512
  local deleted=()
  local cmd arg

  echo -e "+OK Enjoy your mail\r"
  while IFS= read -r line; do
    cmd=${line%% *}
    arg=${line#* }
    case "${cmd^^}" in
      STAT)
        # #msgs and total octets
        echo -e "+OK 1 $mailbox_size\r"
        ;;
      LIST)
        # per-message size
        echo -e "+OK 1 messages ($mailbox_size octets)\r"
        echo -e "1 $mailbox_size\r"
        echo -e ".\r"
        ;;
      RETR)
        if [[ $arg == "1" ]]; then
          echo -e "+OK $mailbox_size octets\r"
          echo -e "From: alice@nfr.lab\r"
          echo -e "To: $USERVAR@$HOST\r"
          echo -e "Subject: Your access code\r"
          echo -e "\r"
          echo -e "Here is your flag:\r"
          echo -e "$FLAG\r"
          echo -e ".\r"
        else
          echo -e "-ERR No such message\r"
        fi
        ;;
      DELE)
        if [[ $arg == "1" ]]; then
          deleted+=(1)
          echo -e "+OK message deleted\r"
        else
          echo -e "-ERR No such message\r"
        fi
        ;;
      NOOP)
        echo -e "+OK\r"
        ;;
      RSET)
        deleted=()
        echo -e "+OK Deletions reset\r"
        ;;
      QUIT)
        # show how many were deleted
        if (( ${#deleted[@]} )); then
          echo -e "+OK Deleting ${#deleted[@]} message(s)\r"
        else
          echo -e "+OK Goodbye\r"
        fi
        break
        ;;
      HELP)
        echo -e "+OK POP3 commands:\r"
        echo -e "  STAT   Mailbox status\r"
        echo -e "  LIST   List message(s)\r"
        echo -e "  RETR   Retrieve message\r"
        echo -e "  DELE   Delete message\r"
        echo -e "  NOOP   No-op\r"
        echo -e "  RSET   Reset deletions\r"
        echo -e "  QUIT   Disconnect\r"
        echo -e ".\r"
        ;;
      *)
        echo -e "-ERR Unknown command\r"
        ;;
    esac
  done
}

main() {
  banner
  auth_loop
  pop3_loop
  # give scanners time to read last lines
  sleep 2
}

main
