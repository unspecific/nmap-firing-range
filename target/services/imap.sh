#!/bin/bash

# ─── Emulator Metadata ─────────────────────────────────────────────────────
EM_PORT="143 993:tls"               # The port this service listens on
EM_VERSION="8.12"               # Optional version identifier
EM_DESC="IMAP4 emulator, brute force enabled"  # Short description for listing output
EM_DAEMON="FakeIMAPd"

correct_user="$USERNAME"
correct_pass="$PASSWORD"
max_attempts=5
attempts=0
authenticated=false

echo -e "* OK $EM_DAEMON/$EM_VERSION Ready [CAPABILITY IMAP4rev1 STARTTLS LOGINDISABLED]\r"

while IFS= read -r line; do
    tag=$(echo "$line" | awk '{print $1}')
    cmd=$(echo "$line" | awk '{print $2}')
    rest=$(echo "$line" | cut -d' ' -f3-)

    case "$cmd" in
        LOGIN)
            username=$(echo "$rest" | awk '{print $1}')
            password=$(echo "$rest" | awk '{print $2}')
            if [[ "$username" == "$correct_user" && "$password" == "$correct_pass" ]]; then
                echo -e "$tag OK LOGIN completed\r"
                authenticated=true
                break
            else
                echo -e "$tag NO LOGIN failed\r"
                attempts=$((attempts + 1))
                if [ "$attempts" -ge "$max_attempts" ]; then
                    echo -e "$tag NO Too many failed attempts\r"
                    exit 0
                fi
            fi
            ;;
        LOGOUT)
            echo -e "* BYE Logging out\r"
            echo -e "$tag OK LOGOUT completed\r"
            exit 0
            ;;
        *)
            echo -e "$tag BAD Unknown or unsupported command\r"
            ;;
    esac
done

# Post-login commands
while IFS= read -r line; do
    tag=$(echo "$line" | awk '{print $1}')
    cmd=$(echo "$line" | awk '{print $2}')

    case "$cmd" in
        SELECT)
            echo -e "* 1 EXISTS\r"
            echo -e "* OK [UIDVALIDITY 1] UIDs valid\r"
            echo -e "$tag OK [READ-WRITE] SELECT completed\r"
            ;;
        LIST)
            echo -e '* LIST (\\HasNoChildren) "/" "INBOX"\r'
            echo -e "$tag OK LIST completed\r"
            ;;
        FETCH)
            echo -e "* 1 FETCH (BODY[TEXT] {42}\r"
            echo -e "$FLAG\r"
            echo -e ")\r"
            echo -e "$tag OK FETCH completed\r"
            ;;
        LOGOUT)
            echo -e "* BYE Logging out\r"
            echo -e "$tag OK LOGOUT completed\r"
            exit 0
            ;;
        *)
            echo -e "$tag BAD Unknown or unsupported command\r"
            ;;
    esac
done
