#!/bin/bash

# ─── Emulator Metadata ─────────────────────────────────────────────────────
EM_PORT="tcp:110 tcp:995:tls"               # The port this service listens on
EM_VERSION="9.72.12"               # Optional version identifier
EM_DAEMON="FakePOP3d"
EM_DESC="POP3 with brute force"  # Short description for listing output

correct_user="$USERNAME"
correct_pass="$PASSWORD"
max_attempts=5
attempts=0
authenticated=false

echo -e "+OK $EM_DAEMON/$EM_VERSION server ready <root@$HOSTNAME>\r"

while IFS= read -r line; do
    case "$line" in
        USER*)
            username="${line#USER }"
            echo -e "+OK User accepted\r"
            ;;
        PASS*)
            password="${line#PASS }"
            if [[ "$username" == "$correct_user" && "$password" == "$correct_pass" ]]; then
                echo -e "+OK Authenticated\r"
                authenticated=true
                break
            else
                echo -e "-ERR Authentication failed\r"
                attempts=$((attempts + 1))
                if [ "$attempts" -ge "$max_attempts" ]; then
                    echo -e "-ERR Too many failed attempts\r"
                    exit 0
                fi
            fi
            ;;
        QUIT)
            echo -e "+OK Bye\r"
            exit 0
            ;;
        *)
            echo -e "-ERR Unknown command\r"
            ;;
    esac
done

# Authenticated session
while IFS= read -r line; do
    case "$line" in
        STAT)
            echo -e "+OK 1 512\r"
            ;;
        LIST)
            echo -e "+OK 1 messages\r"
            echo -e "1 512\r"
            echo -e ".\r"
            ;;
        RETR*)
            echo -e "+OK 512 octets\r"
            echo -e "From: alice@nfr.lab\r"
            echo -e "To: $USERNAME@$HOSTNAME\r"
            echo -e "Subject: Your access code\r"
            echo -e "\r"
            echo -e "Here is your flag:\r"
            echo -e "$FLAG\r"
            echo -e ".\r"
            ;;
        QUIT)
            echo -e "+OK Bye\r"
            exit 0
            ;;
        *)
            echo -e "-ERR Unknown command\r"
            ;;
    esac
done
