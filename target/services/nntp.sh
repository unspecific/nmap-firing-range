#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# ─── Emulator Metadata ─────────────────────────────────────────────────────
EM_PORT="tcp:119 tcp:563:tls"
EM_VERSION="3.1"
EM_DAEMON="FakeNNTP"
EM_DESC="NNTP with brute force enabled"

# ANSI colors
BOLD=$'\e[1m'; CYAN=$'\e[36m'; GREEN=$'\e[32m'; RED=$'\e[31m'; RESET=$'\e[0m'

# Derived
HOST=$(hostname)

banner() {
    printf "%b" "${CYAN}${BOLD}"
    cat <<'EOF'
 _   _  _   _ _____ _______ 
| \ | || \ | |  __ \__   __|
|  \| ||  \| | |__) | | |   
| . ` || . ` |  _  /  | |   
| |\  || |\  | | \ \  | |   
|_| \_||_| \_|_|  \_\ |_|   
EOF
    printf "%b\n" "${RESET}"
    printf "200 %s %s/%s ready\r\n\n" "$HOST" "$EM_DAEMON" "$EM_VERSION"
}

auth_loop() {
    local max=5 attempts=0 user="${USERNAME:-}" pass="${PASSWORD:-}"

    while (( attempts < max )); do
        read -rp "AUTHINFO USER: " inp
        [[ "${inp,,}" =~ ^user[[:space:]]+(.+) ]] || { echo -e "501 Syntax error\r"; continue; }
        attempt_user=${BASH_REMATCH[1]}

        echo -n "AUTHINFO PASS: "
        read -rs attempt_pass
        printf "\r\n"

        if [[ $attempt_user == "$user" && $attempt_pass == "$pass" ]]; then
            echo -e "281 Authentication accepted\r"
            return 0
        else
            (( attempts++ ))
            echo -e "481 Authentication failed (${attempts}/${max})\r"
        fi
    done

    echo -e "483 Too many failures – closing connection\r"
    sleep 1
    exit 1
}

nntp_loop() {
    local flag_group="alt.ctf.challenge"
    local flag_id="<1337@$HOST>"
    local cmd arg

    echo -e "Type HELP for available commands\r"
    while IFS= read -r line; do
        cmd=${line%% *}
        arg=${line#* }
        case "${cmd^^}" in
            HELP)
                echo -e "100 Help text follows\r"
                echo -e "  HELP    Show this help"  
                echo -e "  LIST    List newsgroups"  
                echo -e "  GROUP   Select a group"  
                echo -e "  ARTICLE Retrieve an article"  
                echo -e "  QUIT    Disconnect"  
                echo -e ".\r"
                ;;
            LIST)
                echo -e "215 Newsgroups follow\r"
                echo -e "# system.misc            0 0 n"  
                echo -e "$flag_group         1 1 y\r"
                echo -e ".\r"
                ;;
            GROUP)
                if [[ $arg == "$flag_group" ]]; then
                    echo -e "211 1 1 1 $flag_group\r"
                else
                    echo -e "411 No such newsgroup\r"
                fi
                ;;
            ARTICLE)
                echo -e "220 1 $flag_id article retrieved\r"
                echo -e "From: challenge@nfr.lab\r"
                echo -e "Subject: Welcome to $flag_group\r"
                echo -e "Newsgroups: $flag_group\r"
                echo -e "Message-ID: $flag_id\r\n"
                echo -e "Here’s your flag:\r"
                echo -e "$FLAG\r"
                echo -e ".\r"
                ;;
            QUIT)
                echo -e "205 closing connection – goodbye!\r"
                break
                ;;
            *)
                echo -e "500 Command not recognized\r"
                ;;
        esac
    done
}

main() {
    banner
    auth_loop
    nntp_loop
    # let scanners grab the last lines
    sleep 2
}

main
