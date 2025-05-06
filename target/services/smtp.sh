#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# ─── Emulator Metadata ─────────────────────────────────────────────────────
EM_PORT="tcp:25 tcp:465:tls"
EM_VERSION="6.1"
EM_DAEMON="FakeSMTP"
EM_DESC="SMTP Interface, flag hidden in workflow"

# ANSI colors
BOLD=$'\e[1m'; CYAN=$'\e[36m'; YELLOW=$'\e[33m'; RESET=$'\e[0m'

HOST=$(hostname)
FLAG_EXAMPLE="${FLAG:-}"

banner() {
  printf "%b" "${CYAN}${BOLD}"
  cat <<'EOF'
  _____  __  __ _____ __  __ ______ 
 |  __ \|  \/  |_   _|  \/  |  ____|
 | |__) | \  / | | | | \  / | |__   
 |  ___/| |\/| | | | | |\/| |  __|  
 | |    | |  | |_| |_| |  | | |____ 
 |_|    |_|  |_|_____|_|  |_|______|
EOF
  printf "%b\n\n" "${RESET}"
  echo "220 $HOST ESMTP $EM_DAEMON/$EM_VERSION"
}

smtp_loop() {
  local in_data=false
  local line
  while IFS= read -r line; do
    case "${line^^}" in
      EHLO*|HELO*)
        echo "250-$HOST greets you"
        echo "250-VRFY"
        echo "250-HELP"
        echo "250 OK"
        ;;
      VRFY*)
        # Hidden flag: VRFY returns the flag
        echo "252 ${FLAG_EXAMPLE}"
        ;;
      MAIL\ FROM:*)
        echo "250 OK"
        ;;
      RCPT\ TO:*)
        echo "250 OK"
        ;;
      DATA)
        echo "354 End data with <CR><LF>.<CR><LF>"
        in_data=true
        ;;
      ".")
        if $in_data; then
          echo "250 OK: message accepted"
          in_data=false
        fi
        ;;
      HELP)
        echo "214-Commands supported:"
        echo " MAIL FROM:<addr>"
        echo " RCPT TO:<addr>"
        echo " DATA"
        echo " VRFY <user>"
        echo " QUIT"
        echo "214 End"
        ;;
      QUIT)
        echo "221 Bye"
        break
        ;;
      *)
        if $in_data; then
          # consume message lines
          :
        fi
        # default accept any other command
        echo "250 OK"
        ;;
    esac
  done
}

main() {
  banner
  smtp_loop
  # give Nmap or clients a moment to grab the last banner
  sleep 2
}

main
