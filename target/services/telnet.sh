#!/bin/bash

echo -e "Welcome to FakeTelnet v1.0\r"

correct_user="admin"
correct_pass="letmein"
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
        echo -e "flag{telnet-auth-bypass-1337}\r"
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
