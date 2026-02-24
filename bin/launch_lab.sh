#!/usr/bin/env bash
if [[ "$*" =~ (^| )-V($| ) || "$*" =~ (^| )-l($| ) || "$*" =~ (^| )-h($| ) ]]; then
  SKIP_SUDO=true
fi
# If it's not root, sudo
if [[ $EUID -ne 0 && "$SKIP_SUDO" != "true" ]]; then
  echo " 🔒  Root access required. Re-running with sudo..."
  if [[ "$DEBUG" == "true" ]]; then
    echo "Relaunching in DEBUG mode..."
    exec sudo DEBUG=true "$0" "$@"
  fi
  exec sudo "$0" "$@"
fi

## CONFIG (static, independent of session) ###
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
INSTALL_DIR="$(dirname "$SCRIPT_DIR")"

### CONFIG ###
APP="Nmap Firing Range (NFR) Launcher"
APP_SHORT="NFR Launcher"
VERSION="2.2.9"

THRD_OCT=$(shuf -i2-254 -n1)
SUBNET="192.168.$THRD_OCT"
NUM_SERVICES=5
SESSION_ID=$(openssl rand -hex 4)
NCPORT=$(shuf -i1024-4999 -n1)
NCPORTTLS=$(shuf -i5024-9999 -n1)
SECONDS=0

LAB_DIR="$INSTALL_DIR"
SETUP_LOG="$LAB_DIR/logs/setup.log"
BIN_DIR="bin"
LOG_DIR="logs"
CONF_DIR="conf"
CERT_DIR="certs"
TARGET_DIR="target"
DOMAIN=".nfr.lab"
NFR_GROUP="nfrlab"
DEBUG=${DEBUG:-false}

### FUNCTIONS ###
# ─── Subroutines to make the script work ─────────────────────────────────

# ─── logging & debugging routine ───────────────────────────────── 
log() {
  local mode="$1"; shift
  local message="$*"
  local timestamp="[$(date '+%Y-%m-%d %H:%M:%S')]"
  local header="[$APP_SHORT v$VERSION]"
  local logline="$timestamp $header $message"

  # choose target log: session-specific if ready, otherwise setup.log
  local target="$SETUP_LOG"
  if [[ -n "$SESSION_DIR" && -n "$LOGFILE" ]]; then
    target="$LOGFILE"
  fi

  # console output when requested
  if [[ "$mode" == "console" || "$DEBUG" == "true" ]]; then
    echo -e "$message" >&2
  fi

  # write to log file only when writable (silently skip when running without root)
  local log_dir
  log_dir="$(dirname "$target")"
  if mkdir -p "$log_dir" 2>/dev/null && touch "$target" 2>/dev/null; then
    echo "$logline" >> "$target"
  fi
}

# ─── Create a CA for the session's certs ───────────────────────────────── 
create_ca() {
  log console " 🛡  Generating new CA"
  local ca_dir="$1"  # e.g., "$SESSION_DIR/certs"
  mkdir -p "$ca_dir"

  openssl genrsa -out "$ca_dir/ca.key" 2048
  openssl req -x509 -new -nodes -key "$ca_dir/ca.key" \
    -sha256 -days 365 -out "$ca_dir/ca.crt" \
    -subj "/CN=Lab $SESSION_ID CA"
}

# ─── Create a server cert for the session's servers ───────────────────────────────── 
create_service_cert() {
  local ca_dir="$1"
  local name="$2"        # might be "stealthy-kernel.nfr.lab"
  local ip="$3"          # e.g. "192.168.155.168"

  log console " 🔐  Generating TLS certificate"
  # ─── Normalize the base name ───────────────────────────────────────────────
  # strip any trailing ".nfr.lab"
  local out_dir="$ca_dir/$name"
  local key_file="$out_dir/$name.key"
  local cnf_file="$out_dir/$name.cnf"
  local csr_file="$out_dir/$name.csr"
  local crt_file="$out_dir/$name.crt"

  mkdir -p "$out_dir"

  log silent " 🔐  Generating TLS cert for $name (CA-signed)"

  # 1) Private key (quiet)
  if ! openssl genrsa -out "$key_file" 2048 >/dev/null 2>&1; then
    log console " ❌  Failed to generate key for $name"
    return 1
  fi

  # 2) CSR + SAN config
  cat > "$cnf_file" <<EOF
[ req ]
distinguished_name = req_distinguished_name
req_extensions     = v3_req
prompt             = no

[ req_distinguished_name ]
CN = $name

[ v3_req ]
subjectAltName = @alt_names

[ alt_names ]
DNS.1 = $name
IP.1  = $ip
EOF

  # 3) Generate CSR (quiet)
  if ! openssl req -new \
        -key "$key_file" \
        -out "$csr_file" \
        -config "$cnf_file" \
        -batch -utf8 \
        >/dev/null 2>&1; then
    log console " ❌  Failed to generate CSR for $name"
    return 1
  fi

  # 4) Sign the CSR with our CA (quiet)
  if ! openssl x509 -req \
        -in "$csr_file" \
        -CA "$ca_dir/ca.crt" -CAkey "$ca_dir/ca.key" -CAcreateserial \
        -out "$crt_file" \
        -days 365 -sha256 \
        -extfile "$cnf_file" -extensions v3_req \
        >/dev/null 2>&1; then
    log console " ❌  Failed to sign certificate for $name"
    return 1
  fi

  log silent " ✔  Certificate for $name written to $crt_file"
}

# Check dependancies
check_dependencies() {
  local missing=0
  local cmds=(docker grep shuf tee realpath openssl head od tr)

  # 1) Required binaries
  for cmd in "${cmds[@]}"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      log console " ❌  Missing required command: $cmd"
      missing=1
    fi
  done

  # 2) Docker daemon running?
  if ! docker info >/dev/null 2>&1; then
    log console " ❌  Docker is not running or not accessible by current user."
    missing=1
  fi

  # Determine the Docker image (default placeholder 'any')
  image=$(get_image_for_service "any")

  # Derive archive name by stripping tag and path
  image_base="${image%%:*}"
  archive_name="$(basename "$image_base")"

  tgz_file="$LAB_DIR/conf/${archive_name}.tgz"

  # If image not present, optionally prompt user before loading
  if ! docker image inspect "$image" >/dev/null 2>&1; then
    # In interactive mode, ask permission to load
    if [[ "$UNATTENDED" != true ]]; then
      read -rp "Docker image '$image' not found locally. Load from archive '$tgz_file'? (y/n): " load_resp
      if [[ ! "$load_resp" =~ ^[Yy]$ ]]; then
        log console " ❌  User chose not to load '$image'."
        missing=1
        return
      fi
    fi

    # Proceed to load image from archive
    log console " ℹ️   Loading Docker image '$image' from $tgz_file..."
    if [[ -f "$tgz_file" ]]; then
      if docker load -i "$tgz_file"; then
        log console " ✅  Successfully loaded '$image' from $tgz_file."
      else
        log console " ❌  Failed to load '$image' from $tgz_file."
        missing=1
      fi
    else
      log console " ❌  Archive '$tgz_file' not found; cannot load '$image'."
      missing=1
    fi
  fi

  # 4) Docker Compose plugin or binary
  if docker compose version >/dev/null 2>&1; then
    COMPOSE_CMD="docker compose"
  elif command -v docker-compose >/dev/null 2>&1; then
    COMPOSE_CMD="docker-compose"
  else
    log console " ❌  Neither 'docker compose' (plugin) nor 'docker-compose' found."
    missing=1
  fi

  # 5) Script file sanity check
  local script_file="$INSTALL_DIR/$BIN_DIR/launch_lab.sh"
  if [[ ! -f "$script_file" ]]; then
    log console " ❌  $script_file not found! Please ensure NFR is installed properly."
    log console " 👉  It is recommended to run setup_lab to verify dependencies and set up the environment."
    missing=1
  fi

  # 6) Final verdict
  if [[ $missing -eq 1 ]]; then
    log console " 🚫  One or more required components are missing. Exiting."
    exit 1
  fi

  log console " ✅  All required components are present."
}


# ─── Pre-flight check helpers ─────────────────────────────────────────────────

# check_port_free <port> <proto>
# Returns 0 if the port is free, 1 if already bound on any interface.
# Proto: tcp (default) or udp.
check_port_free() {
  local port="$1" proto="${2:-tcp}"
  local flag
  [[ "$proto" == "udp" ]] && flag="-lun" || flag="-ltn"
  # Column 5 in ss output is Local Address:Port — match lines ending in :<port>
  ss "$flag" 2>/dev/null | awk -v p=":${port}" 'NR>1 && $5 ~ p"$" { found=1 } END { exit found+0 }'
}

# check_ip_forward
# Returns 0 if enabled. Prints a detailed error and returns 1 if not.
check_ip_forward() {
  local val
  val=$(cat /proc/sys/net/ipv4/ip_forward 2>/dev/null || echo "0")
  if [[ "$val" != "1" ]]; then
    log console " ❌  IP forwarding is required for VPN routing but is currently disabled."
    log console "     Enable temporarily : sysctl -w net.ipv4.ip_forward=1"
    log console "     Enable permanently : add 'net.ipv4.ip_forward=1' to /etc/sysctl.conf"
    log console "     NFR will not change this automatically — it may affect your connectivity."
    return 1
  fi
}

# check_ip_unassigned <ip>
# Returns 0 if the IP is not assigned to any interface, 1 if it is.
check_ip_unassigned() {
  local ip="$1"
  if ip addr show 2>/dev/null | grep -q "inet ${ip}/"; then
    return 1
  fi
}

# _list_wifi_interfaces
# Outputs "iface<TAB>status" per line. Status is "free" or "connected (<SSID>)".
_list_wifi_interfaces() {
  local iface ssid
  while IFS= read -r iface; do
    [[ -z "$iface" ]] && continue
    ssid=$(iw dev "$iface" link 2>/dev/null | awk '/SSID/{ print $2; exit }')
    if [[ -n "$ssid" ]]; then
      printf "%s\t%s\n" "$iface" "connected ($ssid)"
    else
      printf "%s\t%s\n" "$iface" "free"
    fi
  done < <(iw dev 2>/dev/null | awk '$1=="Interface"{ print $2 }')
}

# select_wifi_iface [requested_iface]
# Validates or auto-selects a wireless interface for AP mode.
# Prints the chosen interface name on stdout on success.
# Returns 1 and logs a clear error if selection fails or the user cancels.
select_wifi_iface() {
  local requested="${1:-}"
  local -a iface_list=() status_list=()
  local iface status

  while IFS=$'\t' read -r iface status; do
    iface_list+=("$iface")
    status_list+=("$status")
  done < <(_list_wifi_interfaces)

  local count=${#iface_list[@]}

  if [[ $count -eq 0 ]]; then
    log console " ❌  No wireless interfaces found."
    log console "     If you plugged in a USB adapter, verify the OS loaded a driver for it."
    log console "     Run: iw dev"
    return 1
  fi

  if [[ -n "$requested" ]]; then
    # Validate the explicitly specified interface
    local found=false found_status=""
    local i
    for i in "${!iface_list[@]}"; do
      if [[ "${iface_list[$i]}" == "$requested" ]]; then
        found=true
        found_status="${status_list[$i]}"
        break
      fi
    done

    if [[ "$found" == false ]]; then
      log console " ❌  Wireless interface '$requested' was not found."
      log console "     Available interfaces:"
      for i in "${!iface_list[@]}"; do
        log console "       ${iface_list[$i]}    ${status_list[$i]}"
      done
      return 1
    fi

    if [[ "$found_status" != "free" ]]; then
      log console " ⚠️   '$requested' is currently $found_status."
      log console "     Using it as an AP will drop that connection."
      local confirm=""
      read -r -t 30 -p "     Continue? [y/N] " confirm || true
      if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        log console " ℹ️   Cancelled. Specify a different interface with: launch_lab -A <iface>"
        return 1
      fi
    fi

    echo "$requested"
    return 0
  fi

  # No interface specified — auto-select
  if [[ $count -eq 1 ]]; then
    local auto_iface="${iface_list[0]}" auto_status="${status_list[0]}"
    if [[ "$auto_status" != "free" ]]; then
      log console " ⚠️   Only wireless interface found: $auto_iface ($auto_status)"
      log console "     Using it as an AP will drop that connection."
      local confirm=""
      read -r -t 30 -p "     Continue? [y/N] " confirm || true
      if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        log console " ℹ️   Cancelled. Specify a different interface with: launch_lab -A <iface>"
        return 1
      fi
    else
      log console " ℹ️   Using wireless interface: $auto_iface"
    fi
    echo "$auto_iface"
    return 0
  fi

  # Multiple interfaces found — require explicit selection
  log console " ❌  Multiple wireless interfaces found. Specify one with: launch_lab -A <iface>"
  log console ""
  for i in "${!iface_list[@]}"; do
    log console "       ${iface_list[$i]}    ${status_list[$i]}"
  done
  log console ""
  log console "     Example: launch_lab -A ${iface_list[0]}"
  return 1
}

# preflight_checks
# Runs all pre-flight checks based on active mode flags (multi_user, launch_vpn, launch_ap).
# Sets LAN_IP and AP_IFACE as side effects on success.
# Exits with a clear summary if any check fails.
preflight_checks() {
  local errors=0

  # Detect primary LAN IP when multi-user or VPN mode is active
  if [[ "$multi_user" == true || "$launch_vpn" == true ]]; then
    LAN_IP=$(ip route get 1.1.1.1 2>/dev/null | awk '/src/{ print $7; exit }')
    if [[ -z "$LAN_IP" ]]; then
      log console " ❌  Could not detect the primary LAN IP address."
      log console "     Check your network connection or ensure a default route exists."
      (( errors++ )) || :
    fi
  fi

  # -M: WebUI port 80 must be free on the LAN IP
  if [[ "$multi_user" == true && -n "${LAN_IP:-}" ]]; then
    if ! check_port_free "80" "tcp"; then
      log console " ❌  Port 80/TCP is already in use."
      log console "     Multi-user mode binds the WebUI to $LAN_IP:80."
      log console "     Find the conflict: ss -tlnp | grep ':80'"
      (( errors++ )) || :
    fi
  fi

  # -N or -A: IKEv2 VPN ports must be free, ip_forward must be enabled
  if [[ "$launch_vpn" == true ]]; then
    if ! check_port_free "500" "udp"; then
      log console " ❌  Port 500/UDP is already in use."
      log console "     IKEv2 VPN requires this port to be free."
      log console "     Find the conflict: ss -ulnp | grep ':500'"
      (( errors++ )) || :
    fi
    if ! check_port_free "4500" "udp"; then
      log console " ❌  Port 4500/UDP is already in use."
      log console "     IKEv2 VPN NAT-T requires this port to be free."
      log console "     Find the conflict: ss -ulnp | grep ':4500'"
      (( errors++ )) || :
    fi
    if ! check_ip_forward; then
      (( errors++ )) || :
    fi
  fi

  # -A: AP IP must be unassigned, iw must be present, WiFi interface must be selectable
  if [[ "$launch_ap" == true ]]; then
    if ! check_ip_unassigned "10.13.37.1"; then
      log console " ❌  IP address 10.13.37.1 is already assigned to an interface."
      log console "     The WiFi AP requires this address to be available."
      log console "     Check with: ip addr show | grep '10.13.37'"
      (( errors++ )) || :
    fi

    if ! command -v iw >/dev/null 2>&1; then
      log console " ❌  'iw' is required for WiFi AP mode but was not found."
      log console "     Install it: apt-get install iw  (or equivalent for your distro)"
      (( errors++ )) || :
    else
      local selected_iface
      if ! selected_iface=$(select_wifi_iface "${AP_IFACE:-}"); then
        (( errors++ )) || :
      else
        AP_IFACE="$selected_iface"
      fi
    fi
  fi

  # -N or -A: verify wifi-module Docker image is available (offer to load from .tgz)
  if [[ "$launch_vpn" == true || "$launch_ap" == true ]]; then
    local wifi_image="unspecific/fr-wifi-module:1.0"
    local wifi_tgz="$LAB_DIR/conf/fr-wifi-module.tgz"
    if ! docker image inspect "$wifi_image" >/dev/null 2>&1; then
      if [[ -f "$wifi_tgz" ]]; then
        log console " ℹ️   Loading Docker image '$wifi_image' from $wifi_tgz..."
        if docker load -i "$wifi_tgz"; then
          log console " ✅  Loaded '$wifi_image'"
        else
          log console " ❌  Failed to load '$wifi_image' from $wifi_tgz"
          (( errors++ )) || :
        fi
      else
        log console " ❌  Docker image '$wifi_image' not found and no archive at $wifi_tgz."
        log console "     Build it : cd $LAB_DIR/conf && make build-wifi-module"
        log console "     Or load  : cd $LAB_DIR/conf && make load-wifi-module"
        (( errors++ )) || :
      fi
    fi
  fi

  if [[ $errors -gt 0 ]]; then
    log console ""
    log console " 🚫  Pre-flight checks failed ($errors issue(s) listed above)."
    log console "     NFR is non-intrusive and will not modify your system automatically."
    log console "     Resolve the conflicts above and try again."
    exit 1
  fi
}


# Generate a fake flag
generate_flag() {
  local service="$1"
  local rand flag

  # try openssl first
  if rand=$(openssl rand -hex 8 2>/dev/null); then
    rand=${rand^^}                      # uppercase
  else
    # fallback: read 8 bytes and hex-encode
    rand=$(head -c8 /dev/urandom | od -An -tx1 | tr -d ' \n')
    rand=${rand^^}
  fi

  flag="FLAG{$rand}"
  log console " 🔑  Generated flag"
  log silent " Generated FLAG: $flag for $service"
  echo "$flag"
}

### pick a random non-comment/non-blank line from a file ###
_pick_random_entry() {
  local file="$1"
  grep -vE '^\s*#|^\s*$' "$file" 2>/dev/null | shuf -n1
}

# Victim User
get_vuser() {
  log silent "Selecting random victim user"
  local dict_dir="$LAB_DIR/conf/dicts"
  local user_file="$dict_dir/vusers.conf"

  if [[ ! -r "$user_file" ]]; then
    log console " ❌  User dictionary not found or unreadable: $user_file"
    return 1
  fi

  local entry=$(_pick_random_entry "$user_file")
  if [[ -z "$entry" ]]; then
    log console " ❌  No valid users in $user_file"
    return 1
  fi

  echo "$entry"
}

# Victim Password
get_vpass() {
  log silent "Selecting random victim password"
  local dict_dir="$LAB_DIR/conf/dicts"
  local pass_file="$dict_dir/vpasswds.conf"

  if [[ ! -r "$pass_file" ]]; then
    log console " ❌  Password dictionary not found or unreadable: $pass_file"
    return 1
  fi

  local entry=$(_pick_random_entry "$pass_file")
  if [[ -z "$entry" ]]; then
    log console " ❌  No valid passwords in $pass_file"
    return 1
  fi

  echo "$entry"
}

# Victim SNMP Community
get_vcommunity() {
  log silent "Selecting random SNMP community"
  local dict_dir="$LAB_DIR/conf/dicts"
  local comm_file="$dict_dir/communities.conf"

  if [[ ! -r "$comm_file" ]]; then
    log console " ❌  Community dictionary not found or unreadable: $comm_file"
    return 1
  fi

  local entry=$(_pick_random_entry "$comm_file")
  if [[ -z "$entry" ]]; then
    log console " ❌  No valid communities in $comm_file"
    return 1
  fi

  echo "$entry"
}

get_unique_hostname() {
  log silent "Selecting unique hostname"
  local conf_file="$LAB_DIR/conf/dicts/hostname.conf"

  # sanity check
  if [[ ! -r "$conf_file" ]]; then
    log console " ❌  Hostname config not found or unreadable: $conf_file"
    return 1
  fi

  # parse sections
  local section="" line
  local -a adjectives=() nouns=()
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line##*( )}"       # trim leading
    line="${line%%*( )}"       # trim trailing
    [[ -z "$line" || "$line" =~ ^# ]] && continue

    case "$line" in
      "[ADJECTIVES]") section="adj" ;;
      "[NOUNS]")      section="noun" ;;
      *)
        if [[ $section == "adj" ]]; then
          adjectives+=("$line")
        elif [[ $section == "noun" ]]; then
          nouns+=("$line")
        fi
        ;;
    esac
  done < "$conf_file"

  # ensure we have entries
  if (( ${#adjectives[@]} == 0 )) || (( ${#nouns[@]} == 0 )); then
    log console " ❌  Hostname config must include both [ADJECTIVES] and [NOUNS] sections"
    return 1
  fi

  # attempt combinations
  local max_attempts=100
  for ((i=1; i<=max_attempts; i++)); do
    local adj=${adjectives[RANDOM % ${#adjectives[@]}]}
    local noun=${nouns[RANDOM % ${#nouns[@]}]}
    local name="${adj}-${noun}"

    if ! grep -qxF "$name" "$_USED_HOSTNAMES_FILE" 2>/dev/null; then
      echo "$name" >> "$_USED_HOSTNAMES_FILE"
      local fqdn="${name}${DOMAIN}"
      log silent "Chose hostname: $fqdn"
      echo "$fqdn"
      return 0
    fi
  done

  log console " ❌  Unable to generate unique hostname after $max_attempts attempts"
  return 1
}

get_random_ip() {
  log silent "Generating random IP on subnet $SUBNET"
  
  # sanity check
  if [[ -z "$SUBNET" ]]; then
    log console " ❌  SUBNET is not defined"
    return 1
  fi

  local max_attempts=50
  local last_octet ip

  for ((i=1; i<=max_attempts; i++)); do
    last_octet=$(shuf -i130-250 -n1)
    ip="${SUBNET}.${last_octet}"
    if ! grep -qxF "$ip" "$_USED_IPS_FILE" 2>/dev/null; then
      echo "$ip" >> "$_USED_IPS_FILE"
      log silent "Chose IP: $ip"
      echo "$ip"
      return 0
    fi
  done

  log console "❌ Unable to allocate a unique IP after $max_attempts attempts"
  return 1
}

load_session_file() {
  local sess_file="$1"
  local mode="$2"           # e.g. "CONSOLE" or empty
  local src dest dir

  log silent "Loading session file: $sess_file (mode: ${mode:-COPY})"
  src="$LAB_DIR/$sess_file"
  dest="$SESSION_DIR/$sess_file"
  dir="$(dirname "$dest")"

  # 1) Source must exist
  if [[ ! -f "$src" ]]; then
    log console "❌ Missing core config file: $src"
    exit 1
  fi

  # 2) Ensure destination directory
  mkdir -p "$dir" || {
    log console "❌ Failed to create directory: $dir"
    return 1
  }

  # 3) Copy or replace placeholder
  if [[ "$mode" == "CONSOLE" ]]; then
    if sed "s/%CONSOLE%/${SUBNET}.2/" "$src" > "$dest"; then
      log silent "✔ Processed $sess_file with CONSOLE replacement"
    else
      log console "❌ Failed to process placeholder in $sess_file"
      return 1
    fi
  else
    if cp "$src" "$dest"; then
      log silent "✔ Copied $sess_file to session directory"
    else
      log console "❌ Failed to copy $src to $dest"
      return 1
    fi
  fi
}

load_emulated_services() {
  log console " 🔎  Loading emulated services..."
  local services_dir="$LAB_DIR/target/services"
  local script svc port_meta desc version daemon tmp_port

  SERVICE_LIST=()

  # ─── Load each emulator script ──────────────────────────────────────────────
  for script in "$services_dir"/*.sh; do
    [[ -f "$script" ]] || continue
    svc=$(basename "$script" .sh)
    log silent " - Loading $script"

    port_meta=$(parse_meta_var "$script" "EM_PORT")
    desc=$(parse_meta_var "$script" "EM_DESC")
    version=$(parse_meta_var "$script" "EM_VERSION")
    daemon=$(parse_meta_var "$script" "EM_DAEMON")

    if [[ -n "$port_meta" ]]; then
      tmp_port=""
      IFS=' ' read -ra ports <<<"$port_meta"
      for port_proto in "${ports[@]}"; do
        read -r proto port tls <<< "$(awk -F ':' '{print $1, $2, $3}' <<< "$port_proto")"
        if [[ "$tls" ]]; then
          tmp_port+="$proto:$port:tls "
        else
          tmp_port+="$proto:$port "
        fi
      done
      tmp_port=${tmp_port%% }  # trim trailing space

      services["${svc}-em"]="$tmp_port"
      services_meta["${svc}-em"]="$version:$daemon:$desc"
      SERVICE_LIST+=("$svc")
      log silent " ✔️  Loaded emulator: ${svc}-em on $tmp_port"
    else
      log silent " ⚠️  Skipping emulator: $svc (missing EM_PORT)"
    fi
  done

  # ─── List-only mode ─────────────────────────────────────────────────────────
  if [[ "$list_services_only" == true ]]; then
    log silent "List services only starting..."

    echo
    echo " 📋 Target Service Modules:"
    echo " ────────────────────────────────────────────────────────────────────"
    printf "  %-12s\t%-10s\t%-8s\t%s\n" "Service" "Daemon" "Port" "Description"
    printf "  %-12s\t%-10s\t%-8s\t%s\n" "───────" "─────────────" "──────────" "─────────────────────"

    # Real (non-emulated) services
    for key in "${!services[@]}"; do
      if [[ ! "$key" =~ -em$ ]]; then
        IFS=':' read -r ver daemon desc <<<"${services_meta[$key]}"
        IFS=' ' read -ra p_arr <<<"${services[$key]}"
        for pp in "${p_arr[@]}"; do
          proto=$(cut -d':' -f1 <<<"$pp")
          port_num=$(cut -d':' -f2 <<<"$pp")
          tls=$(cut -d':' -f3 <<<"$pp")
          if [[ -n "$tls" ]]; then
            printf "  %-12s\t%-10s\t%-8s\t%s\n" "$key" "${daemon:-N/A}" "${proto}:${port_num}:tls" "${desc:-No description provided} with TLS"
          else
            printf "  %-12s\t%-10s\t%-8s\t%s\n" "$key" "${daemon:-N/A}" "${proto}:${port_num}" "${desc:-No description provided}"
          fi
        done
      fi
    done

    echo
    echo " 📋 Emulated Service Modules:"
    echo " ────────────────────────────────────────────────────────────────────"
    printf "  %-12s\t%-10s\t%-8s\t%s\n" "Service" "Daemon" "Port" "Description"
    printf "  %-12s\t%-10s\t%-8s\t%s\n" "───────" "─────────────" "──────────" "─────────────────────"

    # Emulated services
    for svc in "${SERVICE_LIST[@]}"; do
      local key="${svc}-em"
      IFS=':' read -r ver daemon desc <<<"${services_meta[$key]}"
      IFS=' ' read -ra p_arr <<<"${services[$key]}"
      for pp in "${p_arr[@]}"; do
        proto=$(cut -d':' -f1 <<<"$pp")
        port_num=$(cut -d':' -f2 <<<"$pp")
        tls=$(cut -d':' -f3 <<<"$pp")
        if [[ -n "$tls" ]]; then
          printf "  %-12s\t%-10s\t%-8s\t%s\n" "$key" "${daemon:-N/A}" "${proto}:${port_num}:tls" "${desc:-No description provided} with TLS"
        else
          printf "  %-12s\t%-10s\t%-8s\t%s\n" "$key" "${daemon:-N/A}" "${proto}:${port_num}" "${desc:-No description provided}"
        fi
      done
      [[ "$DEBUG" == "true" ]] && echo " ⏩  ───────────────────────────────────────────────"
    done

    echo
    exit 0
  fi
}

# ─── parse_meta_var ─────────────────────────────────────────────────────────
# Reads VAR from a simple KEY=VALUE file, preserves embedded spaces
parse_meta_var() {
  local file="$1" var="$2" line value

  # 1) File must be readable
  if [[ ! -r "$file" ]]; then
    log console "❌ Cannot read meta file: $file"
    return 1
  fi

  # 2) Grab the last matching line, allow whitespace around “=”
  if ! line=$(grep -E "^[[:space:]]*${var}[[:space:]]*=" "$file" | tail -n1); then
    log silent " ⚠️  No ${var}= entry in $file"
    printf '\n'
    return 0
  fi

  # 3) Strip everything up to the first “=”
  value="${line#*=}"

  # 4) Remove inline comments
  value="${value%%#*}"

  # 6) Trim leading/trailing whitespace
  value="$(printf '%s' "$value" \
    | sed -e 's/^"//' -e 's/"\s*$//')"

  # 7) Emit exactly what remains (spaces intact)
  printf '%s\n' "$value"
}

check_service() {
  local svc="$1"
  local ports="${services[$svc]}"

  if [[ -z "$ports" ]]; then
    log console "❌ Service not supported or not found: $svc"
    exit 1
  fi

  log silent "✔ Found ports for $svc: $ports"
}

create_resolv() {
  local resolv_path="$SESSION_DIR/$TARGET_DIR/conf/resolv.conf"
  local resolv_dir
  resolv_dir="$(dirname "$resolv_path")"

  # ensure the target config directory exists
  if ! mkdir -p "$resolv_dir"; then
    log console "❌ Failed to create directory: $resolv_dir"
    return 1
  fi

  # append our DNS settings
  {
    echo "nameserver ${SUBNET}.2"
    echo "search lan nfr.lab"
    echo "options ndots:0"
  } >> "$resolv_path" || {
    log console "❌ Failed to write DNS config to $resolv_path"
    return 1
  }

  log silent "✔ Wrote DNS resolver config to $resolv_path"
}

add_hosts() {
  local dns_host="$1"
  local dns_ip="$2"
  local tag="# $SESSION_ID"
  local hosts_file="/etc/hosts"

  log console " 🌐  Adding host entry for $dns_host ($dns_ip) to $hosts_file"

  # Remove any previous entries for this session
  if ! sed -i.bak "/${tag//\//\\/}/d" "$hosts_file"; then
    log console " ⚠️  Failed to clean old entries from $hosts_file"
  fi

  # Append the new entry
  if echo -e "${dns_ip}\t${dns_host}\t${tag}" >> "$hosts_file"; then
    log silent " ✔  Added $dns_host to $hosts_file"
  else
    log console " ❌  Failed to append $dns_host to $hosts_file"
    return 1
  fi
}

add_zone_entry() {
  local ip=$1 host=$2
  echo "host-record=$ip,$host,3600" >> "$DNSMASQ_CONF"
}

get_image_for_service() {
  local svc="$1"
  log silent "Selecting image for service $svc"

  # Defaults, override via env:
  local em_prefix="${EMULATOR_IMAGE_PREFIX:-unspecific/victim-v1-tiny}"
  local em_tag="${EMULATOR_IMAGE_TAG:-1.4}"
  local real_prefix="${SERVICE_IMAGE_PREFIX:-unspecific/victim-v1-tiny}"
  local real_tag="${SERVICE_IMAGE_TAG:-1.4}"

  local image
  case "$svc" in
    *-em)
      image="${em_prefix}:${em_tag}"
      ;;
    *)
      image="${real_prefix}:${real_tag}"
      ;;
  esac

  echo "$image"
}

# ─── Helper: reverse an IPv4 address ─────────────────────────────────────────
reverse_ip() {
  local ip="$1"
  # e.g. “192.168.200.254” → “254.200.168.192”
  awk -F. '{ print $4"."$3"."$2"."$1 }' <<<"$ip"
}

# ─── responding to HELP -h ────────────────────────────────
usage() {
  cat <<EOF

$APP_SHORT v$VERSION by Lee 'MadHat' Heath <lheath@unspecific.com>

Spins up a randomized, containerized lab network for Nmap and recon training.
Each session gets a unique /24 subnet, random IPs, randomized hostnames,
randomized credentials, and optional TLS — so no two sessions are the same.
A browser-based dashboard with scoring and a live leaderboard is included.

Usage: $0 [options]

━━━ Session Options ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  -n <number>    Number of target containers to launch (default: $NUM_SERVICES)
  -d             Dry run: generate config but do not start containers
  -i <session>   Replay an existing session by ID (reuse IPs, creds, flags)
  -t             Skip TLS/SSL cert generation (no encrypted ports)
  -p             Skip plain-text (unencrypted) protocols
  -s <service>   Launch only the named service (use -l to list available)

━━━ Access Modes ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  (default: solo — single user on the host machine, no external access)

  -M             Multi-user: expose WebUI on LAN IP, print routing instructions
                   Participants add a static route to reach the lab network.
                   ⚠️  No encryption — use -N or -A for safer multi-user access.

  -N             Network VPN: add IKEv2 VPN (implies -M)
                   Participants connect via IKEv2 VPN from the LAN.
                   Requires: net.ipv4.ip_forward=1, UDP 500/4500 free on LAN IP.

  -A [iface]     WiFi AP: start a WPA2 AP + IKEv2 VPN (implies -M -N)
                   Participants connect to the WiFi AP, get VPN creds from the
                   landing page at 10.13.37.1, then VPN into the lab.
                   Specify iface explicitly or omit to auto-detect.
                   Requires: USB WiFi adapter with AP support, iw installed,
                             net.ipv4.ip_forward=1, UDP 500/4500 free.

  -K <pass>      Override WiFi password (only valid with -A)
                   Must be 8–63 printable ASCII characters.
                   Default: random pick from vpasswds.conf.

━━━ Utility ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  -l             List available services and exit
  -V             Show version and exit
  -h             Show this help message and exit

━━━ Requirements ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  All modes   : Docker + docker compose, unspecific/victim-v1-tiny image
  -N or -A    : unspecific/fr-wifi-module image, net.ipv4.ip_forward=1
  -A          : USB WiFi adapter (AP-capable), iw

━━━ Examples ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  launch_lab                  Solo session, 5 targets
  launch_lab -n 10            Solo session, 10 targets
  launch_lab -M               Multi-user LAN, routing hints printed at launch
  launch_lab -M -N            Multi-user LAN + IKEv2 VPN
  launch_lab -A               WiFi CTF, auto-detect adapter
  launch_lab -A wlan1         WiFi CTF, use wlan1
  launch_lab -A wlan1 -K s3cr3t  WiFi CTF with custom password
  launch_lab -i <session_id>  Replay a previous session exactly

EOF
}

#  _   _ ______ _____    __  __       _       
# | \ | |  ____|  __ \  |  \/  |     (_)      
# |  \| | |__  | |__) | | \  / | __ _ _ _ __  
# | . ` |  __| |  _  /  | |\/| |/ _` | | '_ \ 
# | |\  | |    | | \ \  | |  | | (_| | | | | |
# |_| \_|_|    |_|  \_\ |_|  |_|\__,_|_|_| |_|
#
# this is where the code starts
# we have to declare our starting point.
# this will change soon-ish

declare -A services=(
  ["http"]="tcp:80 tcp:443:tls"
  ["ssh"]="tcp:22"
  ["ftp"]="tcp:21 tcp:990:tls"
  ["smb"]="tcp:139 tcp:445 udp:137 udp:138"
  ["tftp"]="udp:69"
  ["snmp"]="udp:161"
  ["smtp"]="tcp:25 tcp:465:tls"
  ["imap"]="tcp:143 tcp:993:tls"
  ["pop"]="tcp:110 tcp:995:tls"
)

# to make sure we have the same data as the emulated script, we are
# creating a meta_services array that will have the version, daemon, and description
declare -A services_meta=(
  ["http"]="2.0:thttpd:Web server running nginx"
  ["ssh"]="2.0:OpenSSHd:SSH server running openssh server"
  ["ftp"]="1.0:vsFTP:FTP server running vsftpd"
  ["smb"]="1.0:Samba:Samba+shares, brute force enabled"
  ["telnet"]="1.0:Telnet:Telnet server"
  ["other"]="1.0:Unspecific:Custom intrerface"
  ["tftp"]="1.0:tftp-hpa:TFTP server...  tricky"
  ["snmp"]="1.0:net-snmp:SNMP server, guess the community"
  ["smtp"]="1.0:opensmtp:Mail Transport"
  ["imap"]="1.0:imap4d:Check your Mail"
  ["pop"]="1.0:pop3d:Check your Mail"
  ["vnc"]="1.0:VNC:Only available with victim-v2"
)

# Let's look at the options.
# Make sure we identify all the flags used.
# remember process flow
# ─── Defaults ───────────────────────────────────────────────────────────────
dry_run=false
skip_plain=false
skip_tls=false
list_services_only=false
single_service=""
REPLAY_SESSION_ID=""
NUM_SERVICES=5
multi_user=false
launch_vpn=false
launch_ap=false
AP_IFACE=""
AP_PASS=""
LAN_IP=""
VPN_PSK=""

# ─── Pre-process -A [iface] — getopts cannot handle optional arguments ────────
# Scan for -A, capture the optional interface argument, then remove both from $@
# so that getopts can handle the remaining flags normally.
_new_args=()
_i=1
while [[ $_i -le $# ]]; do
  if [[ "${!_i}" == "-A" ]]; then
    launch_ap=true
    _next=$(( _i + 1 ))
    _next_arg="${!_next:-}"
    if [[ -n "$_next_arg" && ! "$_next_arg" =~ ^- ]]; then
      AP_IFACE="$_next_arg"
      (( _i++ )) || :   # skip the interface arg too
    fi
  else
    _new_args+=("${!_i}")
  fi
  (( _i++ )) || :
done
set -- "${_new_args[@]+"${_new_args[@]}"}"
unset _new_args _i _next _next_arg

# ─── Parse Options ────────────────────────────────────────────────────────────
# the leading ':' means we handle missing-arg errors in the case ':'
while getopts ":n:di:pts:lVhMNK:" opt; do
  case "$opt" in
    n)  NUM_SERVICES="$OPTARG" ;;
    d)  dry_run=true ;;
    i)  REPLAY_SESSION_ID="$OPTARG" ;;
    t)  skip_tls=true ;;
    p)  skip_plain=true ;;
    s)  single_service="$OPTARG" ;;
    M)  multi_user=true ;;
    N)  launch_vpn=true ;;
    K)  AP_PASS="$OPTARG" ;;
    l)  list_services_only=true ;;
    V)  echo "$APP_SHORT v$VERSION"; exit 0 ;;
    h)  usage; exit 0 ;;
    :)  echo "❌ Option -$OPTARG requires an argument." >&2; usage; exit 1 ;;
    \?) echo "❌ Invalid option: -$OPTARG" >&2; usage; exit 1 ;;
  esac
done

# ─── Flag implication logic ───────────────────────────────────────────────────
# -A forces -M and -N; -N implies -M
[[ "$launch_ap"  == true ]] && { launch_vpn=true; multi_user=true; }
[[ "$launch_vpn" == true ]] && multi_user=true

# ─── Validate -K passphrase if provided ──────────────────────────────────────
if [[ -n "$AP_PASS" ]]; then
  if [[ ${#AP_PASS} -lt 8 || ${#AP_PASS} -gt 63 ]]; then
    echo "❌ -K passphrase must be 8–63 characters (got ${#AP_PASS})." >&2
    exit 1
  fi
  if [[ "$AP_PASS" =~ [^[:print:]] ]]; then
    echo "❌ -K passphrase contains non-printable characters." >&2
    exit 1
  fi
fi

# ─── -K requires -A ──────────────────────────────────────────────────────────
if [[ -n "$AP_PASS" && "$launch_ap" != true ]]; then
  echo "❌ -K is only valid with -A (WiFi AP mode)." >&2
  usage; exit 1
fi

shift $((OPTIND -1))

# 🚨 Banner
echo
log console " 🎩  $APP v$VERSION - Lee 'MadHat' Heath <lheath@unspecific.com>"


# ─── Check for already-running session ────────────────────────────────────────
if [[ "$list_services_only" != true ]]; then
  _running_nets=$(docker network ls --format ‘{{.Name}}’ 2>/dev/null \
    | grep -E ‘^range-[0-9a-f]{8}$’ || true)
  if [[ -n "$_running_nets" ]]; then
    log console " ⚠️  An NFR lab session is already running:"
    while IFS= read -r _net; do
      _sid="${_net#range-}"
      log console "      session $_sid  (run: cleanup_lab  or replay: launch_lab -i $_sid)"
    done <<< "$_running_nets"
    echo >&2
    read -rp " ❓  Launch a new session alongside? (y/n): " _confirm </dev/tty || _confirm="n"
    if [[ ! "$_confirm" =~ ^[Yy]$ ]]; then
      exit 0
    fi
  fi
  unset _running_nets _net _sid _confirm
fi

# 2) Prepare session folder (unless we’re just listing)
SESSION_TIME=$(date +"%Y-%m-%d_%H-%M-%S")
if [[ "$list_services_only" == true ]]; then
  SESSION_DIR="."
else
  SESSION_DIR="$LAB_DIR/$LOG_DIR/lab_$SESSION_ID"
  mkdir -p "$SESSION_DIR" || {
    log console "❌ Failed to create session directory: $SESSION_DIR"
    exit 1
  }
fi

# ─── Session Environment Variables ───────────────────────────────────────────
LOGFILE="$SESSION_DIR/lab.log"
COMPOSE_FILE="docker-compose.yml"
SCORE_CARD="score_card"
SERVERNAME="$(hostname)"
NETWORK="range-$SESSION_ID"
NUM_SERVICES="${NUM_SERVICES:-5}"
CA_DIR="$SESSION_DIR/$CONF_DIR/$CERT_DIR"
SYSLOG_FILE="$SESSION_DIR/$LOG_DIR/containers"
DNSMASQ_CONF="$SESSION_DIR/$CONF_DIR/console/dnsmasq.conf"
HOSTS="/etc/hosts"
# File-based deduplication — survives subshell calls unlike in-memory arrays
_USED_IPS_FILE="$SESSION_DIR/.used_ips"
_USED_HOSTNAMES_FILE="$SESSION_DIR/.used_hostnames"
touch "$_USED_IPS_FILE" "$_USED_HOSTNAMES_FILE"

# 3) Replay mode?
if [[ -n "$REPLAY_SESSION_ID" ]]; then
  replay_dir="$LAB_DIR/$LOG_DIR/lab_$REPLAY_SESSION_ID"
  replay_compose="$replay_dir/docker-compose.yml"

  log console " 🔁 Replaying session $REPLAY_SESSION_ID..."

  if [[ ! -f "$replay_compose" ]]; then
    log console " ❌ Compose file not found: $replay_compose"
    exit 1
  fi

  log console " 🚀 Launching replay of session $REPLAY_SESSION_ID"
  $COMPOSE_CMD -f "$replay_compose" up -d

  # Restore score card if present
  score_src="$replay_dir/$SCORE_CARD"
  if [[ -f "$score_src" ]]; then
    score_dest="./${SCORE_CARD}_$REPLAY_SESSION_ID"
    cp "$score_src" "$score_dest"
    log console " 📄  Score card restored to $score_dest"
    log console " 📄  Run 'check_lab $score_dest' to view your results."
    chown "${SUDO_USER:-$USER}:${SUDO_USER:-$USER}" "$score_dest"
  fi

  log console " ✅ Session $REPLAY_SESSION_ID relaunched."
  exit 0
fi

# Load emulated services (will exit if -l/list-only)
load_emulated_services

# Load exists app if -l is used
# Otherwise we move forward
# Verify dependencies
check_dependencies
preflight_checks


# ─── Create session directory structure ─────────────────────────────────────
mkdir -p "$SESSION_DIR" || {
  log console " ❌ Failed to create session directory: $SESSION_DIR"
  exit 1
}
mkdir -p \
  "$(dirname "$LOGFILE")" \
  "$(dirname "$COMPOSE_FILE")" \
  "$CA_DIR" \
  "$SESSION_DIR/$LOG_DIR/services" \
  "$SESSION_DIR/$BIN_DIR" \
  "$SESSION_DIR/$CONF_DIR" \
  "$SESSION_DIR/$TARGET_DIR/services" || {
    log console " ❌ Failed to create session directories under $SESSION_DIR"
    exit 1
}
 
# ─── Bootstrap & protect session log & score card ───────────────────────────
touch "$LOGFILE"    && chgrp "$NFR_GROUP" "$LOGFILE"    && chmod 664 "$LOGFILE"
touch "$SESSION_DIR/$SCORE_CARD" && chgrp "$NFR_GROUP" "$SESSION_DIR/$SCORE_CARD" && chmod 664 "$SESSION_DIR/$SCORE_CARD"

log silent " 🗒️  Session $SESSION_ID logging to $LOGFILE"
log console " 📊  Score card initialized at $SESSION_DIR/$SCORE_CARD"


# Verify still running as root
if [[ $EUID -ne 0 ]]; then
  log console "❌ Root privileges are required to continue."
  exit 1
fi

# Start session logging in the session dir
mkdir -p "$(dirname "$LOGFILE")"
touch "$LOGFILE"
log console " 🗒️  Session $SESSION_ID logging to $LOGFILE"


# If the user requested only one service, filter everything else out
if [[ -n "$single_service" ]]; then
  log console " 🚨 Single-Service mode: launching only '$single_service' service"
  check_service "$single_service"

  # Save the chosen service’s port spec and metadata
  port_cfg="${services[$single_service]}"
  meta_cfg="${services_meta[$single_service]}"

  # Re-declare as assoc arrays with just that one entry
  declare -gA services=(
    ["$single_service"]="$port_cfg"
  )
  declare -gA services_meta=(
    ["$single_service"]="$meta_cfg"
  )

  log silent "✔ Configured single service: $single_service => $port_cfg"
  NUM_SERVICES=1
fi

# ─── Initialize session log ──────────────────────────────────────────────────
# Session log
if touch "$LOGFILE"; then
  chgrp "$NFR_GROUP" "$LOGFILE"
  chmod 664 "$LOGFILE"
  log silent "✔ Session log initialized at $LOGFILE"
else
  log console "❌ Cannot create session log file at $LOGFILE"
  exit 1
fi

# Score card
if touch "$SESSION_DIR/$SCORE_CARD"; then
  chgrp "$NFR_GROUP" "$SESSION_DIR/$SCORE_CARD"
  chmod 664 "$SESSION_DIR/$SCORE_CARD"
  log silent "✔ Score card initialized at $SESSION_DIR/$SCORE_CARD"
else
  log console "❌ Cannot create score card file at $SESSION_DIR/$SCORE_CARD"
  exit 1
fi

log silent " 🎩  $APP v$VERSION - Lee 'MadHat' Heath <lheath@unspecific.com>"
log console " 🚀  Launching random lab at $SESSION_TIME"
log console " 🆔  SESSION_ID $SESSION_ID"
# ─── Initialize Score Card ───────────────────────────────────────────────────
cat > "$SESSION_DIR/$SCORE_CARD" <<EOF
# 🎩 Nmap Firing Range ScoreCard - Lee 'MadHat' Heath <lheath@unspecific.com>
#    Started on $SERVERNAME at $SESSION_TIME
session=$SESSION_ID
# hostname=<service_name> service=<service> target=<target_ip> port=<port> proto=<protocol> flag=<flag>
EOF

log console " 📊  Score Card Updated $SESSION_DIR/$SCORE_CARD"

# ─── TLS Setup ───────────────────────────────────────────────────────────────
if [[ "$skip_tls" != true ]]; then
  log silent " 🔐 Creating new CA for session at $CA_DIR"
  mkdir -p "$CA_DIR"
  create_ca "$CA_DIR"
else
  log silent " ⚠️  TLS setup skipped (--no-tls enabled)"
fi

# ─── WiFi AP password ────────────────────────────────────────────────────────
if [[ "$launch_ap" == true && -z "$AP_PASS" ]]; then
  AP_PASS=$(_pick_random_entry "$LAB_DIR/conf/dicts/vpasswds.conf")
  [[ -z "$AP_PASS" ]] && AP_PASS=$(openssl rand -base64 12 | tr -dc 'A-Za-z0-9' | head -c12)
  log silent "✔ Generated WiFi password"
fi

# ─── VPN credentials ─────────────────────────────────────────────────────────
if [[ "$launch_vpn" == true ]]; then
  VPN_PSK=$(openssl rand -base64 24 | tr -dc 'A-Za-z0-9' | head -c 20)
  vpn_endpoint="${LAN_IP}"
  [[ "$launch_ap" == true ]] && vpn_endpoint="10.13.37.1"

  cat > "$SESSION_DIR/vpn.txt" <<VPNEOF
endpoint=${vpn_endpoint}
psk=${VPN_PSK}
network=${SUBNET}.0/24
client_pool=10.99.0.0/24
VPNEOF
  log silent "✔ Generated VPN credentials (endpoint: ${vpn_endpoint})"
fi

# ─── Subnet Announcement ────────────────────────────────────────────────────
log console " 🌐  Creating subnet for scanning: ${SUBNET}.0/24 ($NETWORK)"

# ─── Generate docker-compose.yml Header ────────────────────────────────────
compose_path="$SESSION_DIR/$COMPOSE_FILE"
cat > "$compose_path" <<EOF
# Auto-generated docker-compose.yml (${APP}-v$VERSION) - $(date '+%Y-%m-%d %H:%M:%S')
# SESSION_ID: $SESSION_ID
services:
EOF

log silent "✔ Created docker-compose file: $compose_path"

# ─── Generate services.map Header ────────────────────────────────────────────
services_map="$SESSION_DIR/services.map"
cat >> "$services_map" <<EOF
# Auto-generated services.map (${APP}-v$VERSION) - $(date '+%Y-%m-%d %H:%M:%S')
# Services file for session $SESSION_ID
EOF
log silent "✔ Created $services_map"

# ─── Copy Target Templates ───────────────────────────────────────────────────
if cp -a "$LAB_DIR/$TARGET_DIR/." "$SESSION_DIR/$TARGET_DIR/"; then
  log silent "✔ Copied target directory to session"
else
  log console "❌ Failed to copy $LAB_DIR/$TARGET_DIR to $SESSION_DIR/$TARGET_DIR/"
fi

if chmod -R 755 "$SESSION_DIR/$TARGET_DIR/"; then
  log silent "✔ Set execute permissions on target files"
else
  log console " ⚠️  chmod 755 failed on $SESSION_DIR/$TARGET_DIR/"
fi

# ─── Initialize Session Files ───────────────────────────────────────────────
for f in "$SYSLOG_FILE" \
         "$SESSION_DIR/$TARGET_DIR/score.json" \
         "$SESSION_DIR/$LOG_DIR/tcpdump"; do
  if touch "$f"; then
    chmod 664 "$f" || log console " ⚠️  chmod 664 failed on $f"
    log silent "✔ Initialized $f"
  else
    log console "❌ Cannot create file: $f"
  fi
done

# ─── Load Console & Target Configs ──────────────────────────────────────────
load_session_file "$CONF_DIR/console/rsyslog.conf"
load_session_file "$CONF_DIR/console/dnsmasq.conf"
load_session_file "$TARGET_DIR/conf/rsyslog/rsyslog.conf" "CONSOLE"

# ─── DNS Resolver for Targets ───────────────────────────────────────────────
create_resolv

# ─── Generate Console Service Certificate ───────────────────────────────────
if [[ "$skip_tls" != true ]]; then
  log console " 🔐 Generating TLS certificate for console.nfr.lab"
  mkdir -p "$CA_DIR"  # ensure CA directory exists

  # Note: we pass just “console” here so create_service_cert will append $DOMAIN
  if create_service_cert "$CA_DIR" "console" "$SUBNET.2"; then
    log silent "✔ Certificate for console.nfr.lab created"
  else
    log console "❌ Failed to generate certificate for console.nfr.lab"
    exit 1
  fi
else
  log silent "⚠️  Skipping console certificate (TLS disabled)"
fi

# ─── Add the console service to docker-compose ──────────────────────────────
svc="console"
container_name="${svc}_${SESSION_ID}"
compose_file="$SESSION_DIR/$COMPOSE_FILE"
services_map="$SESSION_DIR/services.map"

# ensure the host entry exists
add_hosts "${svc}.nfr.lab" "${SUBNET}.2"
add_zone_entry "${svc}.nfr.lab" "${SUBNET}.2"
add_zone_entry "host.nfr.lab" "${SUBNET}.254"

# append a nicely indented YAML block
cat >> "$compose_file" <<EOF
  ${svc}:
    image: $(get_image_for_service ${svc})
    container_name: ${container_name}
    hostname: ${svc}.nfr.lab
    networks:
      ${NETWORK}:
        ipv4_address: ${SUBNET}.2
    environment:
      - SESSION_ID=${SESSION_ID}
      - HOSTNAME=${svc}.nfr.lab
      - SERVICE=${svc}$( 
        if [[ "$skip_tls" != true ]]; then
          printf "\n      - SSL_CERT_PATH=/etc/certs/${svc}.nfr.lab/${svc}.nfr.lab.crt\n      - SSL_KEY_PATH=/etc/certs/${svc}.nfr.lab/${svc}.nfr.lab.key"
        fi
      )
    volumes:
      - ${SESSION_DIR}/${CONF_DIR}/certs/${svc}/${svc}.key:/etc/certs/${svc}.nfr.lab/${svc}.nfr.lab.key:ro
      - ${SESSION_DIR}/${CONF_DIR}/certs/${svc}/${svc}.crt:/etc/certs/${svc}.nfr.lab/${svc}.nfr.lab.crt:ro
      - ${SESSION_DIR}/${CONF_DIR}/console/rsyslog.conf:/etc/rsyslog.conf:ro
      - ${SESSION_DIR}/${CONF_DIR}/console/dnsmasq.conf:/etc/dnsmasq.conf:ro
      - ${SESSION_DIR}/${SCORE_CARD}:/etc/score_card:rw
      - ${SESSION_DIR}/mapping.txt:/etc/mapping.txt:rw
      - ${SESSION_DIR}/${TARGET_DIR}/score.json:/etc/score.json:rw
      - ${SYSLOG_FILE}:/var/log/containers:rw
      - ${SESSION_DIR}/${LOG_DIR}/tcpdump:/var/log/tcpdump:rw
      - ${SESSION_DIR}/${TARGET_DIR}:/opt/target:rw
      - ${LAB_DIR}/conf/web_score_card:/opt/web:ro$(
        if [[ "$launch_vpn" == true ]]; then
          printf "\n      - %s/vpn.txt:/etc/vpn.txt:ro" "$SESSION_DIR"
        fi
      )
    expose:
      - "514/udp"
      - "53/udp"
      - "514/tcp"
      - "53/tcp"
      - "443/tcp"$(
        if [[ "$multi_user" == false || "$launch_ap" == true ]]; then
          printf "\n      - \"80/tcp\""
        fi
      )$(
        if [[ "$multi_user" == true && "$launch_ap" == false ]]; then
          printf "\n    ports:\n      - \"%s:80:80\"" "$LAN_IP"
        fi
      )
    command: sh -c "/opt/target/launch_target.sh; /bin/bash"
    restart: unless-stopped

EOF

# record it in services.map
echo "${container_name}" >> "$services_map"
log silent "✔ Added console service ($container_name) to Compose and services.map"

# ─── Prepare victim services and mapping ─────────────────────────────────────
declare -i lab_launch=0
svc_count=1

# initialize mapping.txt
mapping_file="$SESSION_DIR/mapping.txt"
cat > "$mapping_file" <<EOF
# Service → Hostname / IP / Port / Proto / Flag for session $SESSION_ID
EOF
log silent "✔ Initialized mapping file: $mapping_file"

for svc in $(printf "%s\n" "${!services[@]}" | shuf); do
  ((lab_launch++))
  log silent "→ Initializing service: $svc"

  # 1) Allocate IP & hostname
  rand_ip=$(get_random_ip) || exit 1
  svc_hostname=$(get_unique_hostname) || exit 1
  add_zone_entry "$rand_ip" "$svc_hostname"
  echo "$svc,$svc_hostname" >> "$SESSION_DIR/hostnames.map"

  # 2) TLS cert if needed
  if [[ "$skip_tls" != true ]]; then
    create_service_cert "$CA_DIR" "$svc_hostname" "$rand_ip"
  fi

  # 3) Flag, image, and container naming
  flag=$(generate_flag "$svc")
  name="${svc}_host_${SESSION_ID}"
  image=$(get_image_for_service "$svc")
  # 4) Record to score_card (one line per port)
  IFS=' ' read -ra ports <<<"${services[$svc]}"
  for port_proto in "${ports[@]}"; do
    read -r proto port tls <<< "$(awk -F ':' '{print $1, $2, $3}' <<< "$port_proto")"
    echo "hostname= service= target= port= proto= flag=" \
      >> "$SESSION_DIR/$SCORE_CARD"
    echo "$svc: Hostname=$svc_hostname IP=$rand_ip Port=$port Proto=$proto Flag=$flag" \
      >> "$mapping_file"
  done

  echo "$name" >> "$SESSION_DIR/services.map"

  # 6) Generate random credentials
  SESS_USER=$(get_vuser)
  SESS_PASS=$(get_vpass)
  SESS_COMMUNITY=$(get_vcommunity)

  # 7) Append this service to docker-compose.yml
  compose_file="$SESSION_DIR/$COMPOSE_FILE"
  cat >> "$compose_file" <<EOF
  $svc:
    image: $image
    container_name: $name
    hostname: $svc_hostname
    networks:
      $NETWORK:
        ipv4_address: $rand_ip
    expose:
EOF
  for port_proto in "${ports[@]}"; do
    port_proto="${port_proto%\"}"
    port_proto="${port_proto#\"}"
    read -r proto port tls <<< "$(awk -F ':' '{print $1, $2, $3}' <<< "$port_proto")"
    echo "      - \"$port/$proto\"" >> "$compose_file"
    ((svc_count++))
  done

  cat >> "$compose_file" <<EOF
    environment:
      - SESSION_ID=$SESSION_ID
      - IP_ADDRESS=$rand_ip
      - HOSTNAME=$svc_hostname
      - USERNAME=$SESS_USER
      - PASSWORD=$SESS_PASS
      - COMMUNITY=$SESS_COMMUNITY
      - FLAG=$flag
      - SERVICE=$svc
      - PORTS=${services[$svc]}
EOF
  if [[ "$skip_tls" != true ]]; then
    cat >> "$compose_file" <<EOF
      - SSL_CERT_PATH=/etc/certs/$svc_hostname/$svc_hostname.crt
      - SSL_KEY_PATH=/etc/certs/$svc_hostname/$svc_hostname.key
EOF
  fi

  cat >> "$compose_file" <<EOF
    command: sh -c "/opt/target/launch_target.sh; /bin/bash"
    volumes:
      - $SESSION_DIR/$CONF_DIR/certs/${svc_hostname}/${svc_hostname}.key:/etc/certs/${svc_hostname}/${svc_hostname}.key:ro
      - $SESSION_DIR/$CONF_DIR/certs/${svc_hostname}/${svc_hostname}.crt:/etc/certs/${svc_hostname}/${svc_hostname}.crt:ro
      - $SESSION_DIR/target/conf/rsyslog/rsyslog.conf:/etc/rsyslog.conf:ro
      - $SESSION_DIR/$TARGET_DIR:/opt/target:rw
      - $SESSION_DIR/$TARGET_DIR/conf/resolv.conf:/etc/resolv.conf
      - $SESSION_DIR/$LOG_DIR/services:/var/log/services:rw
    logging:
      driver: syslog
      options:
        syslog-address: "udp://${SUBNET}.2:514"
        tag: "{{.Name}}"
        syslog-format: rfc5424

EOF

  if (( NUM_SERVICES > 0 && lab_launch >= NUM_SERVICES )); then
    log silent "✔ Launched $lab_launch services (limit: $NUM_SERVICES)"
    break
  fi

done

# ─── WiFi Module Container ────────────────────────────────────────────────────
if [[ "$launch_vpn" == true || "$launch_ap" == true ]]; then
  wifi_container_name="wifi_module_${SESSION_ID}"

  if [[ "$launch_ap" == true ]]; then
    # AP mode: host networking + privileged (hostapd needs raw socket access)
    cat >> "$compose_file" <<EOF
  fr-wifi-module:
    image: unspecific/fr-wifi-module:1.0
    container_name: ${wifi_container_name}
    network_mode: host
    privileged: true
    environment:
      - AP_ENABLED=true
      - VPN_ENABLED=true
      - AP_IFACE=${AP_IFACE}
      - AP_SSID=nfr-lab
      - AP_PASS=${AP_PASS}
      - AP_IP=10.13.37.1
      - AP_CHANNEL=6
      - VPN_ENDPOINT=10.13.37.1
      - VPN_PSK=${VPN_PSK}
      - VPN_SUBNET=${SUBNET}.0/24
      - VPN_CLIENT_POOL=10.99.0.0/24
      - VPN_DNS=${SUBNET}.2
    volumes:
      - ${LAB_DIR}/conf/web_score_card/vpn.html:/opt/wifi-module/web/index.html:ro
      - ${LAB_DIR}/conf/web_score_card/cgi-bin/vpn_info.cgi:/opt/wifi-module/web/cgi-bin/vpn_info.cgi:ro
      - ${SESSION_DIR}/vpn.txt:/etc/vpn.txt:ro
    restart: unless-stopped

EOF
  else
    # VPN-only mode: standard Docker network, ports bound to LAN IP only
    cat >> "$compose_file" <<EOF
  fr-wifi-module:
    image: unspecific/fr-wifi-module:1.0
    container_name: ${wifi_container_name}
    cap_add:
      - NET_ADMIN
    ports:
      - "${LAN_IP}:500:500/udp"
      - "${LAN_IP}:4500:4500/udp"
    networks:
      ${NETWORK}:
    environment:
      - AP_ENABLED=false
      - VPN_ENABLED=true
      - VPN_ENDPOINT=${LAN_IP}
      - VPN_PSK=${VPN_PSK}
      - VPN_SUBNET=${SUBNET}.0/24
      - VPN_CLIENT_POOL=10.99.0.0/24
      - VPN_DNS=${SUBNET}.2
    restart: unless-stopped

EOF
  fi

  echo "$wifi_container_name" >> "$services_map"
  log silent "✔ Added fr-wifi-module container ($wifi_container_name) to Compose"
fi

# ─── Append network section ────────────────────────────────────────────────
compose_file="$SESSION_DIR/$COMPOSE_FILE"
cat >> "$compose_file" <<EOF
networks:
  ${NETWORK}:
    ipam:
      config:
        - subnet: ${SUBNET}.0/24
          gateway: ${SUBNET}.254
EOF
log silent "✔ Finished creating Compose file: $compose_file"

if docker compose -f "$compose_file" config --quiet; then
  log console " ✅  Docker-Compose config valid, launching stack…"
else
  log console "❌ Docker-Compose config is invalid – aborting!"
  exit 1
fi

# adjust svc_count (it was incremented once past the last)
((svc_count--))

# ─── Set ownership on score card ───────────────────────────────────────────
REAL_USER="${SUDO_USER:-$USER}"
chown "${REAL_USER}:${REAL_USER}" "${SESSION_DIR}/${SCORE_CARD}"
ln -sf "${SESSION_DIR}/${SCORE_CARD}" "$SCORE_CARD"

# ─── Dry-run support ───────────────────────────────────────────────────────
if [[ "$dry_run" == true ]]; then
  log silent " 🏁  Dry-run mode enabled"
  log console " 🗂  Configured $lab_launch targets with $svc_count open ports"
  log console " ⛔  Dry run complete. To start containers, run:"
  log console "   ${COMPOSE_CMD} -f \"$compose_file\" up -d"
  echo
  exit 0
else
  log console " 🚀  Launching $lab_launch targets with $svc_count open ports. Good luck!"
fi

# ─── Launch containers ─────────────────────────────────────────────────────
if ! $COMPOSE_CMD -f "$compose_file" create >/dev/null 2>&1; then
  log console "❌  Failed to create the containers"
  exit 1
fi

if ! $COMPOSE_CMD -f "$compose_file" start >/dev/null 2>&1; then
  log console "❌  Failed to start the containers"
  exit 1
fi


# ─── Show running containers ────────────────────────────────────────────────
log silent " ✅  Final container list:"
if DOCKER_PS=$($COMPOSE_CMD ps --format 'table {{.Names}}\t{{.Ports}}' 2>&1); then
  log silent "$DOCKER_PS"
else
  log silent "⚠️  Could not retrieve container list"
fi

log console " 🎉  Your Nmap Firing Range is ready for testing!\n\r"
log console "    **** Targets have been launched. ****\r\n          **** The range is hot. ****"
log console " Start your adventure with this command:"
log console "     nmap -v $SUBNET.0/24"
log console "  try adding --dns-servers $SUBNET.2 for nme resolution."
log console "         or visit http://console.nfr.lab/"
echo

# ─── Mode-specific access info ────────────────────────────────────────────────
if [[ "$launch_ap" == true ]]; then
  log console " 📡  WiFi AP active"
  log console "     SSID     : nfr-lab"
  log console "     Password : $AP_PASS"
  log console "     Connect to WiFi, then visit http://10.13.37.1/ for VPN setup"
  echo
fi

if [[ "$launch_vpn" == true ]]; then
  log console " 🔒  IKEv2 VPN Access"
  log console "     Endpoint  : ${vpn_endpoint}"
  log console "     PSK       : $VPN_PSK"
  log console "     Lab net   : ${SUBNET}.0/24"
  log console "     Client IPs: 10.99.0.0/24"
  log console ""
  log console "  Windows : Settings → VPN → Add → IKEv2 · Auth: Pre-shared key"
  log console "  macOS   : System Settings → VPN → Add → IKEv2 · Shared Secret"
  log console "  Linux   : sudo ipsec up nfr-vpn"
  log console "  iOS     : Settings → VPN → Add → IKEv2"
  log console "  Android : Settings → VPN → IKEv2/IPSec PSK"
  echo
fi

if [[ "$multi_user" == true && "$launch_ap" == false ]]; then
  log console " 🌐  Multi-user mode: WebUI is accessible on your LAN"
  log console "     URL      : http://${LAN_IP}/"
  log console ""
  log console " 📡  Routing instructions for LAN participants:"
  log console "     Linux/macOS : sudo ip route add ${SUBNET}.0/24 via ${LAN_IP}"
  log console "     Windows     : route add ${SUBNET}.0 mask 255.255.255.0 ${LAN_IP}"
  log console ""
  if [[ "$launch_vpn" == false ]]; then
    log console " ⚠️   Running -M without -N gives unencrypted lab access."
    log console "     Consider -N (VPN) or -A (WiFi AP) for safer multi-user access."
  fi
  echo
fi

# ─── Report duration ───────────────────────────────────────────────────────
duration=$SECONDS
log console " ⏱️  Lab launched in $duration seconds"
