#!/bin/bash

# service_emulator.sh - lightweight service emulation script
# Emulates basic interaction for text-based protocols (FTP, SMTP, etc.) for testing and Nmap banner detection
# Usage: ./service_emulator.sh <service> <flag>

DEBUG=${DEBUG:-false}

echo $ENV >> "/var/log/containers"

# Allow CLI args to override env vars
if [[ -n "$1" ]]; then SERVICE="$1"; fi
if [[ -n "$2" ]]; then FLAG="$2"; fi
if [[ -n "$3" ]]; then PORT="$3"; fi

SERVICE="${SERVICE:-}"
FLAG="${FLAG:-}"
PORT="${PORT:-}"

launch_em() {
  if [[ -n "$1" ]]; then local launch_service="$1"; fi
  if [[ -n "$2" ]]; then local launch_port="$2"; fi
  if [[ -n "$3" ]]; then local launch_tls=true; fi
  
  echo "[*] Launching with $local_service on $launch_port $launch_tls"
  if ss -ltn | grep -q ":$launch_port"; then
    echo "❌ Port $launch_port is already in use. Aborting."
    return
  fi
  if [[ $launch_tls ]]; then
    NC_LISTENER=true ncat -k -l "$launch_port" --ssl --ssl-cert "$SSL_CERT_PATH" --ssl-key "$SSL_KEY_PATH" --exec "/bin/bash $emulator" 2>/dev/null
  else 
    NC_LISTENER=true ncat -k -l "$PORT" --exec "/bin/bash $emulator" 2>/dev/null
  fi
  return
}

if [[ -z "$SERVICE" || -z "$FLAG" ]]; then
  echo "Usage: $0 <service> <flag>"
  exit 1
fi

emulator="${SERVICE}.sh"
if [[ ! -f $emulator ]]; then
  echo " ❌  Emulator script $emulator does."
  exit 1
fi
if [[ ! $PORT ]]; then
  PORT=$(grep -oP 'EM_PORT="\K([^"]*)' $emulator)
fi

IFS=' ' read -ra ports <<< "${PORT}"
for port_proto in "${ports[@]}"; do
  proto=$(cut -d':' -f1 <<< "$port_proto")
  port=$(cut -d':' -f2 <<< "$port_proto")
  tls=$(cut -d':' -f3 <<< "$port_proto")
  if [[ $tls == "tls" ]]; then
    echo "Launching $emulator with TLS on port $port"
    launch_emulator "$emulator" "$port" "tls"
  else
    echo "Launching $emulator on port $port"
    launch_emulator "$emulator" "$port"
  fi
done

exit 0

