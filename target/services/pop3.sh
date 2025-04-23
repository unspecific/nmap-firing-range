#!/bin/bash

correct_user="bob"
correct_pass="hunter2"
max_attempts=5
attempts=0
authenticated=false

echo -e "+OK Fake POP3 server ready <12345@example.com>\r"

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
            echo -e "From: alice@example.com\r"
            echo -e "To: $username@example.com\r"
            echo -e "Subject: Your access code\r"
            echo -e "\r"
            echo -e "Here is your flag:\r"
            echo -e "flag{pop3-rfc1939-fun}\r"
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
