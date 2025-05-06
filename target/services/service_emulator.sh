#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# ─── service_emulator.sh ──────────────────────────────────────────────────
# Launch protocol emulators based solely on environment variables.
# Required env vars:
#   SERVICE         - Base name of emulator script (SERVICE.sh)
#   FLAG            - Flag string to inject into the emulator
#   PORTS           - Space-separated list of port specs: proto:port[:tls]
# Optional env vars:
#   SSL_CERT_PATH   - Path to TLS certificate (for tls ports)\#   SSL_KEY_PATH    - Path to TLS key (for tls ports)
#   DEBUG=true|false - Enable debug output

# Validate required environment
: "${SERVICE:?Environment variable SERVICE is required}"  # e.g. "ssh", "smtp"
: "${FLAG:?Environment variable FLAG is required}"
: "${PORTS:?Environment variable PORTS is required}"  # e.g. "tcp:22 tcp:443:tls"

# Export FLAG for all emulators
export FLAG

# Locate the emulator script
emulator="${SERVICE}.sh"
if [[ ! -x "$emulator" ]]; then
  echo "ERROR: Emulator script '$emulator' not found or not executable" >&2
  exit 1
fi

# Helper to launch an emulator on one port
launch() {
  local proto="$1" port="$2" tls_flag="$3"

  # Check if port is free
  if ss -ltn sport = :"$port" >/dev/null; then
    echo "ERROR: Port $port is already in use" >&2
    return 1
  fi

  # Build ncat command
  if [[ "$tls_flag" == "tls" ]]; then
    if [[ -z "${SSL_CERT_PATH:-}" || -z "${SSL_KEY_PATH:-}" ]]; then
      echo "ERROR: SSL_CERT_PATH and SSL_KEY_PATH must be set for TLS on port $port" >&2
      return 1
    fi
    cmd=(ncat -k -l "$port" --ssl \
         --ssl-cert "$SSL_CERT_PATH" --ssl-key "$SSL_KEY_PATH" \
         --sh-exec "/bin/bash '$PWD/$emulator'")
  else
    cmd=(ncat -k -l "$port" \
         --sh-exec "/bin/bash '$PWD/$emulator'")
  fi

  # Debug output
  if [[ "${DEBUG:-false}" == "true" ]]; then
    echo "DEBUG: Launching \${SERVICE} on port \$port (tls=\$tls_flag)"
    echo "DEBUG: Command: \${cmd[*]}"
  fi

  # Start listener in background
  "\${cmd[@]}" &
}

# Iterate through each port spec in PORTS
echo "Launching emulator '$SERVICE' with FLAG"
for spec in $PORTS; do
  IFS=':' read -r proto port tls_flag <<< "$spec"
  if [[ "${proto,,}" != "tcp" ]]; then
    [[ "${DEBUG:-false}" == "true" ]] && echo "Skipping non-TCP spec: $spec"
    continue
  fi
  launch "$proto" "$port" "$tls_flag"
done

# Wait for all background ncat processes to exit
wait
