#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'
SRV=$1
FLG=$2
SRV_LOC="/opt/target/services/"

launch_log="/opt/target/$HOSTNAME.launch_log"
touch "$launch_log"

trap 'log "🧹 Cleaning up service: $SERVICE"; pkill -P $$; exit 0' SIGINT SIGTERM

log() {
  local message="$1"
  local timestamp="[$(date '+%Y-%m-%d %H:%M:%S')]"
  echo -e "$timestamp $0 $message" >> "$launch_log"
}

# ─── Emulator Launcher ─────────────────────────────────────────────────────
launch() {
  local proto="$1" port="$2" tls_flag="${3:-}"

  if [[ -z "$proto" || -z "$port" || -z "${IP_ADDRESS:-}" ]]; then
    log "ERROR: Missing required values. proto=$proto port=$port IP=$IP_ADDRESS"
    return 1
  fi

  log "Preparing to launch $SRV on $IP_ADDRESS $proto/$port (tls=$tls_flag)"

  # Check if port is already in use on this IP
  if netstat -ltn | awk '{print $4}' | grep -qE "$IP_ADDRESS:$port\$"; then
    log "ERROR: Port $port already in use on $IP_ADDRESS"
    echo "ERROR: Port $port is already in use on $IP_ADDRESS" >&2
    return 1
  fi

  if [[ "$tls_flag" == "tls" ]]; then
    if [[ -z "${SSL_CERT_PATH:-}" || -z "${SSL_KEY_PATH:-}" ]]; then
      log "ERROR: TLS requested but cert or key not set"
      return 1
    fi
    cmd=(ncat -k -l --ssl \
         --ssl-cert "$SSL_CERT_PATH" --ssl-key "$SSL_KEY_PATH" \
         --sh-exec "/bin/bash $emulator" "$IP_ADDRESS" "$port")
    log "Launching TLS emulator on $IP_ADDRESS $proto/$port"
  else
    if [[ $proto == "udp" ]]; then
      cmd=(ncat -u -k -l --sh-exec "/bin/bash $emulator" "$IP_ADDRESS" "$port")
    else
      cmd=(ncat -k -l --sh-exec "/bin/bash $emulator" "$IP_ADDRESS" "$port")
      log "Launching emulator on $IP_ADDRESS $proto/$port"
    fi
  fi

  if [[ "${DEBUG:-false}" == "true" ]]; then
    log "DEBUG: Command: ${cmd[*]}"
  fi

  "${cmd[@]}" &
}

log "  service_emulator launched $0 $@"
log "  Service call for $SRV"

# ─── Environment Validation ────────────────────────────────────────────────
: "${SERVICE:?Environment variable SERVICE is required}"
: "${FLAG:?Environment variable FLAG is required}"
: "${PORTS:?Environment variable PORTS is required}"  # e.g. "tcp:22 tcp:443:tls"

# Check for required tools
command -v ncat >/dev/null || { echo "ERROR: ncat is not installed." >&2; exit 1; }
command -v netstat >/dev/null || { echo "ERROR: netstat is not installed." >&2; exit 1; }

# Locate the emulator script
emulator="/opt/target/services/${SRV}.sh"
if [[ ! -x "$emulator" ]]; then
  log "ERROR: Emulator script '$emulator' not found or not executable"
  exit 1
fi

# ─── Main Launch Loop ──────────────────────────────────────────────────────
log " 🚀  Launching emulator '$SERVICE'"

 IFS=' ' read -ra ports <<<"$PORTS"
for spec in "${ports[@]}"; do
  IFS=':' read -r proto port tls_flag <<< "$spec"
  log "What Data will be used to launch the service $proto $port $tls_flag "

  # if [[ "${proto,,}" != "tcp" ]]; then
  #  [[ "${DEBUG:-false}" == "true" ]] && log "Skipping non-TCP spec: $spec"
  #  continue
  #fi

  launch "$proto" "$port" "$tls_flag"
done

log "✅ All listeners launched. Waiting for shutdown signal..."
wait
