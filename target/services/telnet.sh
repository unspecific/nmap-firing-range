#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# ─── Emulator Metadata ─────────────────────────────────────────────────────
EM_PORT="tcp:23 tcp:992:tls"
EM_VERSION="3.14"
EM_DAEMON="FakeTELNETd"
EM_DESC="Telnet server, brute force enabled"

# ANSI colors
RED=$'\e[31m'; GREEN=$'\e[32m'; CYAN=$'\e[36m'; BOLD=$'\e[1m'; RESET=$'\e[0m'

banner() {
    printf "%b" "${CYAN}${BOLD}"
    cat <<'EOF'
  _   _                        
 | \ | |                       
 |  \| |_ __ ___   __ _ _ __   
 | . ` | '_ ` _ \ / _` | '_ \  
 | |\  | | | | | | (_| | |_) | 
 |_| \_|_| |_| |_|\__,_| .__/  
  ______ _      _      | |     
 |  ____(_)    (_)     |_|     
 | |__   _ _ __ _ _ __   __ _  
 |  __| | | '__| | '_ \ / _` | 
 | |    | | |  | | | | | (_| | 
 |_|    |_|_|  |_|_| |_|\__, | 
  _____                  __/ | 
 |  __ \                |___/  
 | |__) |__ _ _ __   __ _  ___ 
 |  _  // _` | '_ \ / _` |/ _ \
 | | \ \ (_| | | | | (_| |  __/
 |_|  \_\__,_|_| |_|\__, |\___|
                     __/ |     
                    |___/      

EOF
    printf "%b\n\n" "${RESET}"
    printf " Welcome to %s v%s\n\n" "$EM_DAEMON" "$EM_VERSION"
}

auth_loop() {
    local max_attempts=5
    local attempts=0
    local user="${USERNAME:-}"
    local pass="${PASSWORD:-}"

    while (( attempts < max_attempts )); do
        local left=$(( max_attempts - attempts ))
        read -rp "login (attempts left: ${left}): " attempt_user
        read -rsp "Password: " attempt_pass
        printf "\n"

        if [[ $attempt_user == "$user" && $attempt_pass == "$pass" ]]; then
            printf "%bLogin successful!%b\n\n" "$GREEN" "$RESET"
            return 0
        fi

        printf "%bLogin incorrect.%b\n\n" "$RED" "$RESET"
        (( attempts++ ))
    done

    printf "%bToo many failed attempts – disconnecting.%b\n" "$RED" "$RESET"
    sleep 2
    exit 1
}

shell_loop() {
    printf "Type 'help' for commands. Have fun!\n\n"
    local cmd
    while true; do
        read -rp "${BOLD}${EM_DAEMON}> ${RESET}" cmd
        case $cmd in
            help)
                echo "  help        Show this message"
                echo "  ls          List files"
                echo "  cat flag.txt   Show the flag"
                echo "  exit        Disconnect"
                ;;
            ls)
                echo "flag.txt   notes.txt"
                ;;
            "cat flag.txt")
                echo "$FLAG"
                ;;
            "cat notes.txt")
                echo "# Nothing suspicious here…"
                ;;
            exit)
                printf "Bye!\n"
                break
                ;;
            *)
                printf "bash: %s: command not found\n" "$cmd"
                ;;
        esac
    done
}

main() {
    banner
    auth_loop
    shell_loop
    # ensure Nmap etc. can still see everything
    sleep 2
}

main
