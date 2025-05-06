#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

launch_log="/opt/target/$HOSTNAME.launch_log"
touch "$launch_log"

trap 'log "🧹 Cleaning up service: $SERVICE"; pkill -P $$; exit 0' SIGINT SIGTERM

log() {
  local message="$1"
  local timestamp="[$(date '+%Y-%m-%d %H:%M:%S')]"
  echo "$timestamp $message" >> "$launch_log"
}

# ─── Environment Validation ────────────────────────────────────────────────
: "${SERVICE:?Environment variable SERVICE is required}"
: "${FLAG:?Environment variable FLAG is required}"
: "${PORTS:?Environment variable PORTS is required}"  # e.g. "tcp:22 tcp:443:tls"

# Check for required tools
command -v ncat >/dev/null || { echo "ERROR: ncat is not installed." >&2; exit 1; }
command -v netstat >/dev/null || { echo "ERROR: netstat is not installed." >&2; exit 1; }

# Locate the emulator script
emulator="/opt/target/services/${SERVICE%-em}.sh"
if [[ ! -x "$emulator" ]]; then
  log "ERROR: Emulator script '$emulator' not found or not executable"
  exit 1
fi

# ─── Emulator Launcher ─────────────────────────────────────────────────────
launch() {
  local proto="$1" port="$2" tls_flag="${3:-}"

  if [[ -z "$proto" || -z "$port" ]]; then
    log "ERROR: Malformed port spec '$proto:$port:$tls_flag'"
    return 1
  fi

  log "Preparing to launch $SERVICE on $proto/$port (tls=$tls_flag)"

  if netstat -ltn | awk '{print $4}' | grep -qE "[:.]$port\$"; then
    log "ERROR: Port $port is already in use"
    echo "ERROR: Port $port is already in use" >&2
    return 1
  fi

  if [[ "$tls_flag" == "tls" ]]; then
    if [[ -z "${SSL_CERT_PATH:-}" || -z "${SSL_KEY_PATH:-}" ]]; then
      log "ERROR: TLS requested but SSL_CERT_PATH or SSL_KEY_PATH missing"
      echo "ERROR: TLS cert/key not set for $port" >&2
      return 1
    fi
    cmd=(ncat -k -l "$port" --ssl \
         --ssl-cert "$SSL_CERT_PATH" --ssl-key "$SSL_KEY_PATH" \
         --sh-exec "/bin/bash '$PWD/$emulator'")
    log "Launching TLS version of $SERVICE on port $port"
  else
    cmd=(ncat -k -l "$port" \
         --sh-exec "/bin/bash '$PWD/$emulator'")
    log "Launching plain version of $SERVICE on port $port"
  fi

  if [[ "${DEBUG:-false}" == "true" ]]; then
    log "DEBUG: Launch cmd: ${cmd[*]}"
  fi

  "${cmd[@]}" &  # Safe array execution with quoting
}

# ─── Main Launch Loop ──────────────────────────────────────────────────────
log "🚀 Launching emulator '$SERVICE'"

for spec in $PORTS; do
  IFS=':' read -r proto port tls_flag <<< "$spec"

  if [[ "${proto,,}" != "tcp" ]]; then
    [[ "${DEBUG:-false}" == "true" ]] && log "Skipping non-TCP spec: $spec"
    continue
  fi

  launch "$proto" "$port" "$tls_flag"
done

log "✅ All listeners launched. Waiting for shutdown signal..."
wait
