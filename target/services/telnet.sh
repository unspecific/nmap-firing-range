#!/bin/bash

# ─── Emulator Metadata ─────────────────────────────────────────────────────
EM_PORT="tcp:23 tcp:992:tls"               # The port this service listens on
EM_VERSION="3.14"               # Optional version identifier
EM_DAEMON="FakeTELNETd"
EM_DESC="Telnet server, brute force enables"  # Short description for listing output


echo -e "Welcome to ${EM_DAEMON} v${EM_VERSION}\r"

correct_user="$USERNAME"
correct_pass="$PASSWORD"
max_attempts=5
attempts=0

while [ $attempts -lt $max_attempts ]; do
    echo -e "login: \c"
    read username
    echo -e "Password: \c"
    read -s password
    echo -e "\n\r"

    if [[ "$username" == "$correct_user" && "$password" == "$correct_pass" ]]; then
        echo -e "Login successful\r"
        echo -e "$FLAG\r"
        break
    else
        echo -e "Login incorrect\r"
        attempts=$((attempts + 1))
    fi
done

if [ $attempts -ge $max_attempts ]; then
    echo -e "Too many failed login attempts. Disconnecting.\r"
fi

# Hold the connection briefly so Nmap/etc can still grab the last output
sleep 2
