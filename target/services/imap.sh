#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# ─── Emulator Metadata ─────────────────────────────────────────────────────
EM_PORT="tcp:143 tcp:993:tls"
EM_VERSION="8.12"
EM_DAEMON="FakeIMAPd"
EM_DESC="IMAP4 emulator, brute force enabled"

# ANSI colors
BOLD=$'\e[1m'; CYAN=$'\e[36m'; GREEN=$'\e[32m'; RED=$'\e[31m'; RESET=$'\e[0m'

# Configurable
MAX_ATTEMPTS=5
USERVAR="${USERNAME:-}"
PASSVAR="${PASSWORD:-}"
HOST=$(hostname)

banner() {
  printf "%b" "${CYAN}${BOLD}"
  cat <<'EOF'
 _____      _           _____                      
|_   _|    | |         |  __ \                     
  | | _ __ | |_ ___    | |  | | __ _ _ __ ___  ___ 
  | || '_ \| __/ _ \   | |  | |/ _` | '__/ __|/ _ \
 _| || | | | ||  __/   | |__| | (_| | |  \__ \  __/
/_____||_| |_|\__\___|  |_____/ \__,_|_|  |___/\___|
EOF
  printf "%b\n" "${RESET}"
  echo -e "* OK [$EM_DAEMON/$EM_VERSION] IMAP4rev1 Ready\r"
}

auth_loop() {
  local attempts=0
  local tag user pass

  while (( attempts < MAX_ATTEMPTS )); do
    IFS= read -r line
    tag=${line%% *}
    # Expect: A001 LOGIN <user> <pass>
    if [[ "${line^^}" =~ ^[A-Z0-9]+[[:space:]]+LOGIN[[:space:]]+([^[:space:]]+)[[:space:]]+(.+)$ ]]; then
      user=${BASH_REMATCH[1]}
      pass=${BASH_REMATCH[2]}
    else
      echo -e "$tag BAD Expecting: LOGIN <user> <pass>\r"
      continue
    fi

    if [[ $user == "$USERVAR" && $pass == "$PASSVAR" ]]; then
      echo -e "$tag OK LOGIN completed\r"
      return 0
    else
      (( attempts++ ))
      echo -e "$tag NO LOGIN failed (${attempts}/${MAX_ATTEMPTS})\r"
    fi
  done

  echo -e "$tag NO Too many failures – closing\r"
  sleep 1
  exit 1
}

imap_loop() {
  local tag cmd args
  local mailbox="INBOX"
  local exists=1

  while IFS= read -r line; do
    tag=${line%% *}
    cmd=${line#* }; cmd=${cmd%% *}
    args=${line#* }; args=${args#* }; args=${args#*}

    case "${cmd^^}" in
      CAPABILITY)
        echo -e "* CAPABILITY IMAP4rev1 STARTTLS IDLE AUTH=PLAIN\r"
        echo -e "$tag OK CAPABILITY completed\r"
        ;;
      LIST)
        # LIST "" "*"
        echo -e "* LIST (\\HasNoChildren) \"/\" \"INBOX\"\r"
        echo -e "* LIST (\\HasNoChildren) \"/\" \"Junk\"\r"
        echo -e "$tag OK LIST completed\r"
        ;;
      SELECT)
        # SELECT INBOX
        if [[ "${args^^}" == "INBOX" ]]; then
          echo -e "* ${exists} EXISTS\r"
          echo -e "* OK [UIDVALIDITY 1] UIDs valid\r"
          echo -e "$tag OK [READ-WRITE] SELECT completed\r"
        else
          echo -e "$tag NO No such mailbox\r"
        fi
        ;;
      FETCH)
        # FETCH 1 BODY[TEXT]
        if [[ "$args" =~ ^1[[:space:]]+BODY\[TEXT\] ]]; then
          echo -e "* 1 FETCH (BODY[TEXT] {${#FLAG}})\r"
          echo -e "$FLAG\r"
          echo -e ")\r"
          echo -e "$tag OK FETCH completed\r"
        else
          echo -e "$tag NO Invalid FETCH args\r"
        fi
        ;;
      NOOP)
        echo -e "$tag OK NOOP completed\r"
        ;;
      LOGOUT)
        echo -e "* BYE Logging out\r"
        echo -e "$tag OK LOGOUT completed\r"
        break
        ;;
      *)
        echo -e "$tag BAD Unknown command\r"
        ;;
    esac
  done
}

main() {
  banner
  auth_loop
  imap_loop
  # let scanners grab last lines
  sleep 2
}

main
