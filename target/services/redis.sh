#!/bin/bash

echo -ne "+OK FakeRedis 6.6.6 ready for connections\r\n"

while IFS= read -r line; do
    # Optional logging
    echo "[*] Received: $line"

    # Respond to fake GET command
    if echo "$line" | grep -qi "GET"; then
        echo -ne "\$27\r\nflag{redis-key-access-win}\r\n"
    elif echo "$line" | grep -qi "INFO"; then
        echo -ne "# Server\r\nredis_version:6.6.6\r\n"
        echo -ne "# Clients\r\nconnected_clients:1\r\n"
        echo -ne "# Keyspace\r\ndb0:keys=1,expires=0,avg_ttl=0\r\n"
        echo -ne "\r\n"
    elif echo "$line" | grep -qi "AUTH"; then
        echo -ne "-NOAUTH Authentication required.\r\n"
    elif echo "$line" | grep -qi "PING"; then
        echo -ne "+PONG\r\n"
    elif echo "$line" | grep -qi "SET"; then
        echo -ne "+OK\r\n"
    elif echo "$line" | grep -qi "FLUSHALL"; then
        echo -ne "+OK\r\n"
    elif [[ "$line" == "QUIT" ]]; then
        echo -ne "+OK Goodbye.\r\n"
        break
    else
        echo -ne "-ERR unknown command '$line'\r\n"
    fi
done
