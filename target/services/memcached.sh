#!/bin/bash
# ncat -kl 11211 --sh-exec "/launch/fake_memcached.sh" &
# ─── Emulator Metadata ─────────────────────────────────────────────────────
EM_PORT="tcp:11211"               # The port this service listens on
EM_VERSION="6.1"               # Optional version identifier
EM_DAEMON="memfaked"
EM_DESC="Key-Value temp storage"  # Short description for listing output


echo -e "VERSION ${EM_VERSION}_${EM_DAEMON}\r"

while IFS= read -r line; do
    echo "[*] Received: $line"

    cmd=$(echo "$line" | awk '{print tolower($1)}')

    case "$cmd" in
        stats)
            echo -e "STAT pid 31337\r"
            echo -e "STAT uptime 123456\r"
            echo -e "STAT version $EM_VERSION\r"
            echo -e "STAT curr_items 1\r"
            echo -e "STAT bytes 1337\r"
            echo -e "STAT curr_connections 2\r"
            echo -e "END\r"
            ;;
        get)
            key=$(echo "$line" | awk '{print $2}')
            if [[ "$key" == "flag" ]]; then
                echo -e "VALUE flag 0 27\r"
                echo -e "$FLAG\r"
                echo -e "END\r"
            else
                echo -e "END\r"
            fi
            ;;
        set)
            key=$(echo "$line" | awk '{print $2}')
            echo -e "STORED\r"
            ;;
        flush_all)
            echo -e "OK\r"
            ;;
        quit)
            echo -e "Bye\r"
            break
            ;;
        *)
            echo -e "ERROR\r"
            ;;
    esac
done
