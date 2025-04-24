#!/bin/bash
# fake_smtp.sh — Basic SMTP simulation with banner, EHLO, and MAIL FROM handling

# ─── Emulator Metadata ─────────────────────────────────────────────────────
EM_PORT="9999"               # The port this service listens on
EM_VERSION="1.1"               # Optional version identifier
EM_DAEMON="Unspecific MTA"
EM_DESC="Custom interface"  # Short description for listing output


echo "220 fake-smtp.local ESMTP Postfix"

while read -r line; do
    case "$line" in
        EHLO*|HELO*)
            echo "250-fake-smtp.local Hello"
            echo "250-AUTH PLAIN LOGIN"
            echo "250 OK"
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
            if [ "$in_data" = true ]; then
                echo "250 OK: message accepted"
                in_data=false
            fi
            ;;
        QUIT)
            echo "221 Bye"
            break
            ;;
        *)
            echo "250 OK"
            ;;
    esac
done
