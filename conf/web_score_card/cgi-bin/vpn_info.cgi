#!/bin/sh
printf "Content-Type: application/json\r\n\r\n"

f=/etc/vpn.txt
if [ ! -s "$f" ]; then
  printf '{"enabled":false}\n'
  exit 0
fi

endpoint=$(grep '^endpoint=' "$f" | cut -d= -f2-)
psk=$(grep '^psk=' "$f" | cut -d= -f2-)
username=$(grep '^username=' "$f" | cut -d= -f2-)
password=$(grep '^password=' "$f" | cut -d= -f2-)
network=$(grep '^network=' "$f" | cut -d= -f2-)

printf '{"enabled":true,"endpoint":"%s","psk":"%s","username":"%s","password":"%s","network":"%s"}\n' \
  "$endpoint" "$psk" "$username" "$password" "$network"
