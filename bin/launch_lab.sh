#!/bin/bash
if [[ "$*" =~ (^| )-V($| ) || "$*" =~ (^| )-l($| ) || "$*" =~ (^| )-h($| ) ]]; then
  SKIP_SUDO=true
fi
# If it's not root, sudo
if [[ $EUID -ne 0 && "$SKIP_SUDO" != "true" ]]; then
  echo "🔒 Root access required. Re-running with sudo..."
  if [[ "$DEBUG" == "true" ]]; then
    echo "Relaunching in DEBUG mode..."
    exec sudo DEBUG=true "$0" "$@"
  fi 
  exec sudo "$0" "$@"
fi

### CONFIG ###
APP="Nmap Firing Range (NFR) Launcher"
APP_SHORT="NFR Launcher"
VERSION="2.0"

THRD_OCT=$(shuf -i2-254 -n1)
SUBNET="192.168.$THRD_OCT"
USED_IPS=()
NUM_SERVICES=5
SESSION_ID=$(openssl rand -hex 4)
NCPORT=$(shuf -i1024-4999 -n1)
NCPORTTLS=$(shuf -i5024-9999 -n1)
SECONDS=0

LAB_DIR="/opt/firing-range"
BIN_DIR="bin"
LOG_DIR="logs"
CONF_DIR="conf"
CERT_DIR="certs"
TARGET_DIR="target"
DOMAIN=".nfr.lab"
NFR_GROUP="nfrlab"
DEBUG=${DEBUG:-false}

### FUNCTIONS ###
log() {
  local mode="$1"
  shift
  local message=$*
  local log
  log="[$(date '+%Y-%m-%d %H:%M:%S')] [$APP_SHORT v$VERSION] $message"

  if [[ "$mode" == "console" || "$DEBUG" == "true" ]]; then
    echo "$message"
  fi
  if [[ -f $LOGFILE ]]; then
    echo "$log" >> "$LOGFILE"
  else
    echo "$log" >> "$LAB_DIR/$LOG_DIR/setup.log"
  fi
}

#######################################################################
# if the user wants TLS, we first create a CA
#
create_ca() {
  log console " 🛡  Generating new CA"
  local ca_dir="$1"  # e.g., "$SESSION_DIR/certs"
  mkdir -p "$ca_dir"

  openssl genrsa -out "$ca_dir/ca.key" 2048
  openssl req -x509 -new -nodes -key "$ca_dir/ca.key" \
    -sha256 -days 365 -out "$ca_dir/ca.crt" \
    -subj "/CN=Lab $SESSION_ID CA"
}

#######################################################################
# we will also create a cert for ech host launched
create_service_cert() {
  local ca_dir="$1"
  local name="$2"        # e.g. ftp_host
  local ip="$3"          # e.g. 192.168.200.101
  local out_dir="$ca_dir/$name"
  mkdir -p "$out_dir"
  log console " 🛡  Generating new certificate for *****.nfr.lab"

  openssl genrsa -out "$out_dir/$name.key" 2048

  cat > "$out_dir/$name.cnf" <<EOF
[ req ]
distinguished_name = req_distinguished_name
req_extensions = v3_req
prompt = no

[ req_distinguished_name ]
CN = $name

[ v3_req ]
subjectAltName = @alt_names

[ alt_names ]
DNS.1 = $name
IP.1 = $ip
EOF

  openssl req -new -key "$out_dir/$name.key" \
    -out "$out_dir/$name.csr" \
    -config "$out_dir/$name.cnf" 

  openssl x509 -noout -req \
    -in "$out_dir/$name.csr" \
    -CA "$ca_dir/ca.crt" -CAkey "$ca_dir/ca.key" -CAcreateserial \
    -out "$out_dir/$name.crt" \
    -days 365 -sha256 \
    -extfile "$out_dir/$name.cnf" -extensions v3_req 2>/dev/null
}
#######################################################################

# Check dependancies
check_dependencies() {
  local missing=0

  # Required commands
  for cmd in docker grep shuf tee realpath openssl; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      echo " ❌  Missing required command: $cmd"
      missing=1
    fi
  done

  # Check Docker is running
  if ! docker info >/dev/null 2>&1; then
    echo " ❌  Docker is not running or not accessible by current user."
    missing=1
  fi

  # Optional: Check for required Alpine base image
  if ! docker image inspect alpine >/dev/null 2>&1; then
    echo " ℹ️   Alpine image not found. Pulling it now..."
    docker pull alpine || { echo " ❌  Failed to pull Alpine image."; missing=1; }
  fi

  # Optional: Check network driver
  # if ! docker network ls | grep -q "$NETWORK"; then
  #  echo " ℹ️   Docker network $NETWORK not found. It will be created by the script."
  # fi

  # Check for Docker Compose (V2 or V1 fallback)
  if ! docker compose version &>/dev/null; then
    echo " ❌  'docker compose' is not available. Please install Docker Compose V2."
    missing=1
  fi
  
  # Ensure the script exists before continuing
  SCRIPT_FILE="$LAB_DIR/$BIN_DIR/launch_lab.sh"
  if [[ ! -f "$SCRIPT_FILE" ]]; then
    echo " ❌  $SCRIPT_FILE not found! Please ensure NFR is installed properly."
    echo " 👉  It is recommended to run setup_lab to verify dependancies, setup the environemnt."
    missing=1
  fi


  # exit with error if anything is missing
  if [[ $missing -eq 1 ]]; then
    echo " 🚫  One or more required components are missing. Exiting."
    exit 1
  fi

  echo " ✅  All required components are present."
}

# Generate a fake flag
generate_flag() {
  echo "FLAG{$(openssl rand -hex 8)}"
}

get_vuser() {
  log silent "Grabbing a random victim user"
  local user_file="$LAB_DIR/conf/vusers.conf"

  if [[ ! -f "$user_file" ]]; then
    echo "❌ User file not found: $user_file" >&2
    return 1
  fi

  # Filter out empty or comment lines, then pick a random user
  shuf -n 1 < <(grep -vE '^\s*#|^\s*$' "$user_file")
}

get_vpass() {
  log silent "Grabbing a random victim password"
  local pass_file="$LAB_DIR/conf/vpasswds.conf"

  if [[ ! -f "$pass_file" ]]; then
    echo "❌ Password file not found: $pass_file" >&2
    return 1
  fi

  # Filter out empty or comment lines, then pick a random password
  shuf -n 1 < <(grep -vE '^\s*#|^\s*$' "$pass_file")
}

get_vcommunity() {
  log silent "Grabbing a random victim snmp community"
  local comm_file="$LAB_DIR/conf/communities.conf"

  if [[ ! -f "$comm_file" ]]; then
    echo "❌ Community file not found: $comm_file" >&2
    return 1
  fi

  # Filter out empty or comment lines, then pick a random password
  shuf -n 1 < <(grep -vE '^\s*#|^\s*$' "$comm_file")
}

get_unique_hostname() {
  local conf_file="$LAB_DIR/conf/hostname.conf"
  [[ -f "$conf_file" ]] || {
    echo "❌ Hostname config not found: $conf_file" >&2
    return 1
  }

  local in_section=""
  local adjectives=()
  local nouns=()

  # Read and categorize lines
  while IFS= read -r line || [[ -n "$line" ]]; do
    line=$(echo "$line" | xargs)  # Trim whitespace
    [[ -z "$line" || "$line" =~ ^# ]] && continue

    case "$line" in
      "[ADJECTIVES]") in_section="adjective" ;;
      "[NOUNS]")      in_section="noun" ;;
      *)
        if [[ "$in_section" == "adjective" ]]; then
          adjectives+=("$line")
        elif [[ "$in_section" == "noun" ]]; then
          nouns+=("$line")
        fi
        ;;
    esac
  done < "$conf_file"

  local max_attempts=100
  local attempt=0

  while (( attempt++ < max_attempts )); do
    local adj=${adjectives[$RANDOM % ${#adjectives[@]}]}
    local noun=${nouns[$RANDOM % ${#nouns[@]}]}
    local name="${adj}-${noun}"

    if [[ -z "${USED_HOSTNAMES[$name]}" ]]; then
      USED_HOSTNAMES["$name"]=1
      echo "${name}${DOMAIN}"
      return 0
    fi
  done

  echo "❌ Unable to generate unique hostname after $max_attempts attempts" >&2
  return 1
}

get_random_ip() {
  while :; do
    last_octet=$(shuf -i130-250 -n1)
    ip="$SUBNET.$last_octet"
    if [[ ! " ${USED_IPS[*]} " =~ $ip ]]; then
      USED_IPS+=("$ip")
      echo "$ip"
      return
    fi
  done
}

load_session_file() {
  local sess_file="$1"
  log silent "Loading $sess_file into $LABDIR"
  if [[ -f "$LAB_DIR/$sess_file" ]]; then
    cp "$LAB_DIR/$sess_file" "$SESSION_DIR/$sess_file" || log console "❌ Can't copy $sess_file to session Continuing..."
  else 
    echo "❌ Missing core config file for console server. $sess_file Please reinstall or update"
    exit 1
  fi
}


load_emulated_services() {
  log console "🔎 Loading target services..."
  local services_dir="$LAB_DIR/target/services"
  local script svc port desc version

  SERVICE_LIST=()

  for script in "$services_dir"/*.sh; do
    [[ -f "$script" ]] || continue
    log silent " - Loading $script"

    svc=$(basename "$script" .sh)
    port=$(parse_meta_var "$script" "EM_PORT")
    desc=$(parse_meta_var "$script" "EM_DESC")
    version=$(parse_meta_var "$script" "EM_VERSION")
    daemon=$(parse_meta_var "$script" "EM_DAEMON")

    if [[ -n "$port" ]]; then
      IFS=' ' read -ra ports <<< "${port}"
      for port_proto in "${ports[@]}"; do
        proto=$(cut -d':' -f1 <<< "$port_proto")
        port=$(cut -d':' -f2 <<< "$port_proto")
        tls=$(cut -d':' -f3 <<< "$port_proto")
        if [[ -n "$tls" ]]; then
          services["${svc}-em"]="$proto:$port:tls"
        else 
          services["${svc}-em"]="$proto:$port"
        fi
      done
      SERVICE_LIST+=("$svc")
      log silent "✔️  Loaded emulator: ${svc}-em on $port"
    else
      log silent "⚠️  Skipping emulator: $svc (missing EM_PORT)"
    fi
  done

  if [[ "$list_services_only" == true ]]; then
    log silent "List services Only startng..."

    # header and formating for crisp output
    echo
    echo " 📋 Target Service Modules:"
    echo " ────────────────────────────────────────────────────────────────────"
    printf "  %-12s\t%-10s\t%-8s\t%s\n" "Service" "Daemon" "Port" "Description"
    printf "  %-12s\t%-10s\t%-8s\t%s\n" "───────" "─────────────" "──────────" "─────────────────────"


    # List full services
    for svc in $(printf "%s\n" "${!services[@]}"); do
      if [[ ! "$svc" =~ "-em"$ ]]; then
        local details="${services_meta[$svc]}"
        ver=$(cut -d':' -f1 <<< "$details")
        daemon=$(cut -d':' -f2 <<< "$details")
        desc=$(cut -d':' -f3 <<< "$details")
        IFS=' ' read -ra ports <<< "${services[$svc]}"
        for port_proto in "${ports[@]}"; do
          proto=$(cut -d':' -f1 <<< "$port_proto")
          port=$(cut -d':' -f2 <<< "$port_proto")
          tls=$(cut -d':' -f3 <<< "$port_proto")
          if [[ -n "$tls" ]]; then
            printf "  %-12s\t%-10s\t%-8s\t%s\n" "${svc}" "${daemon:-N/A}" "${proto:-N/A}:${port:-N/A}:tls" "${desc:-No description provided} with TLS"
          else 
            printf "  %-12s\t%-10s\t%-8s\t%s\n" "${svc}" "${daemon:-N/A}" "${proto:-N/A}:${port:-N/A}" "${desc:-No description provided}"
          fi
        done
      fi
    done

    # Now let's look at the Emulated services we just loaded.
    echo
    echo " 📋 Emulated Service Modules:"
    echo " ────────────────────────────────────────────────────────────────────"
    printf "  %-12s\t%-10s\t%-8s\t%s\n" "Service" "Daemon" "Port" "Description"
    printf "  %-12s\t%-10s\t%-8s\t%s\n" "───────" "─────────────" "──────────" "─────────────────────"

    # List emulated services
    for svc in "${SERVICE_LIST[@]}"; do
      script="$services_dir/${svc}.sh"
      log silent "👁‍🗨 Loading service $svc in $script"
      port=$(parse_meta_var "$script" "EM_PORT")
      desc=$(parse_meta_var "$script" "EM_DESC")
      version=$(parse_meta_var "$script" "EM_VERSION")
      daemon=$(parse_meta_var "$script" "EM_DAEMON")
      IFS=' ' read -ra ports <<< "${port}"
      log silent "👁‍🗨 Grabbed port=\"${port}\", daemon = \"${daemon}\", version=\"${version}\", desc=\"${desc}\" for $svc" 
      # for 
      for port_proto in "${ports[@]}"; do
        proto=$(cut -d':' -f1 <<< "$port_proto")
        port=$(cut -d':' -f2 <<< "$port_proto")
        tls=$(cut -d':' -f3 <<< "$port_proto")
        if [[ -n "$tls" ]]; then
          printf "  %-12s\t%-10s\t%-8s\t%s\n" "${svc}-em" "${daemon:-N/A}" "${proto:-N/A}:${port:-N/A}:tls" "${desc:-No description provided} with TLS"
        else 
          printf "  %-12s\t%-10s\t%-8s\t%s\n" "${svc}-em" "${daemon:-N/A}" "${proto:-N/A}:${port:-N/A}" "${desc:-No description provided}"
        fi
      done
    if [[ "$DEBUG" == "ture" ]]; then
       echo "⏩ ───────────────────────────────────────────────"
    fi
    done
    echo
    exit 0
  fi
}

parse_meta_var() {
  local file="$1"
  local var="$2"
  # log silent "👁‍🗨 Parsing ${var} config line from ${file} "
  grep -E "^$var=" "$file" | cut -d= -f2- | cut -d"#" -f1 | sed 's/^ *//; s/ *$//;' | tr -d '"'
}


get_image_for_service() {
  case $1 in
    *-em) echo "unspecific/victim-v1-tiny:1.3" ;;
    *) echo "unspecific/victim-v1-tiny:1.3" ;;
  esac
}


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
  ["http"]="2.0:mini_httpd:Web server running nginx"
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

while getopts "ln:hdVi:tp" opt; do
  case "$opt" in
    n)
      NUM_SERVICES="$OPTARG"
      ;;
    d)
      DO_NOT_RUN=true
      ;;
    h)
      echo
      echo "$APP v$VERSION by Lee 'MadHat' Heath <lheath@unspecifc.com>"
      echo "$APP_SHORT sets up a virtual lab network of containerized targets for offensive security testing."
      echo "Each lab session is unique with randomized IPs, hostnames, services, and flags."
      echo "Targets support full TLS using a session-specific certificate authority (CA)."
      echo "Sessions are fully scorable using the score_card system, and all labs are replayable."
      echo "Perfect for practicing Nmap scanning, service fingerprinting, brute forcing, and flag hunting."
      echo
      echo "Usage: $0 [options]"
      echo
      echo "Options:"
      echo "  -n <number>      Launch specified number of targets (default: 5)"
      echo "  -d               Dry run (do not launch Docker containers)"
      echo "  -i <SESSION_ID>  Replay existing session"
      echo "  -t               Skip TLS/SSL cert generation and encrypted connections"
      echo "  -p               Skip Plain text (unencrypted) protocols"
      echo "  -l               List available services (both native and emulated)"
      echo "  -V               Show version and exit"
      echo "  -h               Show this help message"
      echo
      exit 0
      ;;
    l)
      list_services_only=true
      ;;
    V)
      echo
      echo " 🎩  $APP v$VERSION - Lee 'MadHat' Heath <lheath@unspecific.com>"
      echo 
      exit 0
      ;;
    i)
      REPLAY_SESSION_ID="$OPTARG"
      ;;
    p)
      skip_plain=true
      ;;
    t)
      sklp_tls=true
      ;;
    \?)
      echo "❌ Invalid option: -$OPTARG" >&2
      exit 1
      ;;
    :)
      echo "❌ Option -$OPTARG requires an argument." >&2
      exit 1
      ;;
    *)
      echo "Invalid option. Use -h for help."
      exit 1
      ;;
  esac
done

# 🚨 Let's introduce ourselves
echo
echo " 🎩  $APP v$VERSION - Lee 'MadHat' Heath <lheath@unspecific.com>"

check_dependencies

# Prepare session folder
SESSION_TIME=$(date +"%Y-%m-%d_%H-%M-%S")
if [[ "$list_services_only" != true ]]; then
  SESSION_DIR="$LAB_DIR/$LOG_DIR/lab_$SESSION_ID"
else
  SESSION_DIR="."
fi

# If we are just replaying, we can stop here
#
if [[ -n "${REPLAY_SESSION_ID:-}" ]]; then
  SESSION_DIR="/opt/firing-range/logs/lab_$REPLAY_SESSION_ID"
  COMPOSE_FILE="$SESSION_DIR/docker-compose.yml"

  echo "🔁 Replaying session $REPLAY_SESSION_ID..."

  if [[ ! -f "$COMPOSE_FILE" ]]; then
    echo "❌ docker-compose.yml not found in $SESSION_DIR"
    exit 1
  fi
  log console " 🚀  Launching Replay of Session $REPLAY_SESSION_ID"
  docker compose -f "$COMPOSE_FILE" up -d
  if [[ -f "$SESSION_DIR/score_card" ]]; then
    cp "$SESSION_DIR/score_card" "./score_card_$REPLAY_SESSION_ID"
    echo "📄 Score card restored to ./score_card_$REPLAY_SESSION_ID"
    echo "📄 run 'check_lab score_card_$REPLAY_SESSION_ID' to check your card"
    REAL_USER="${SUDO_USER:-$USER}"
    chown "$REAL_USER:$REAL_USER" "./score_card_$REPLAY_SESSION_ID"
  fi
  echo "✅ Session $REPLAY_SESSION_ID relaunched."
  exit 0
fi

# Last option before we build
load_emulated_services
# Make sure no one made it this far without root
if [[ $EUID -ne 0 ]]; then
  echo "❌ Root privileges are required to continue."
  exit 1
fi


# Otherwise it's time to build the lab

LOGFILE="$SESSION_DIR/lab.log"
COMPOSE_FILE="docker-compose.yml"
SCORE_CARD="score_card"
HOSTNAME=$(hostname)
NETWORK=range-$SESSION_ID
NUM_SERVICES="${NUM_SERVICES:-5}"
CA_DIR="$SESSION_DIR/${CONF_DIR}/${CERT_DIR}"
SYSLOG_FILE="$SESSION_DIR/$LOG_DIR/containers"
ZONEFILE="$SESSION_DIR/$CONF_DIR/nfr.lab.zone"
declare -A USED_HOSTNAMES=()

# create lab session environment
mkdir -p "$SESSION_DIR" "$CA_DIR" "$SESSION_DIR/$LOG_DIR"
mkdir -p "$SESSION_DIR/$BIN_DIR" "$SESSION_DIR/$CONF_DIR"
mkdir -p "$SESSION_DIR/$TARGET_DIR" "$SESSION_DIR/$TARGET_DIR/services"
echo "--------- NEW SESSION $SESSION_ID ------------------" > $LOGFILE || echo "cant create logfile"
chgrp $NFR_GROUP $LOGFILE
chmod 664 $LOGFILE
log silent "Initiated a new session directory $SESSION_DIR"

#initiate the zone file
echo "$SUBNET.254     host.nfr.lab" >> "$ZONEFILE"
echo "$SUBNET.2     console.nfr.lab" >> "$ZONEFILE"

log silent " 🎩  $APP v$VERSION - Lee 'MadHat' Heath <lheath@unspecific.com>"
log console " 🚀  Launching random lab at $SESSION_TIME"
log console " 🆔  SESSION_ID $SESSION_ID"
{
  echo "# 🎩 Nmap Firing Range ScoreCard - Lee 'MadHat' Heath <lheath@unspecific.com>" 
  echo "#    Started on $HOSTNAME at $SESSION_TIME"
  echo "session=$SESSION_ID"
  echo "# service=telnet target=${SUBNET}.153 port=5537 proto=tcp flag=FLAG{89ea16740}"
} > "$SCORE_CARD"
log console " 📊  Score Card Created"


if [[ "$skip_tls" != true ]]; then
  log silent "🔐 Creating new CA for session at $CA_DIR"
  create_ca "$CA_DIR"
else
  log silent "⚠️  TLS setup skipped (--no-tls enabled)"
fi

log console " 🌐  Creating Subnet for Scanning - ${SUBNET}.0/24 - $NETWORK"
# moved to Docker Compose

# Start docker-compose.yml
{
  echo "# Auto-generated docker-compose.yml (${APP}-v$VERSION) - $(date)"
  echo "# SESSION_ID: $SESSION_ID"
  echo "services:"
} > "$SESSION_DIR/$COMPOSE_FILE"
log silent " Created docker-compose.yaml - ${SESSION_DIR}/${COMPOSE_FILE}"

{
  echo "# Auto-generated services.map (${APP}-v$VERSION) - $(date)"
  echo "# Services file for sesion $SESSION_ID"
} >> "$SESSION_DIR/services.map"
log silent " Created ${SESSION_DIR}/services.map"

# set up the lab console (console.nfr.lab)
load_session_file "$CONF_DIR/rsyslog.conf"
load_session_file "$CONF_DIR/dnsmasq.conf"

cp -a "$LAB_DIR/$TARGET_DIR" "$SESSION_DIR/"
chmod -R 755 "$SESSION_DIR/$TARGET_DIR/" || echo "chmod of $SESSION_DIR/$TARGET_DIR/ failed" 
touch $SYSLOG_FILE
chmod 664 $SYSLOG_FILE || echo "can't chmod $SYSLOG_FILE"

######################################################################
# if TLS is used
  if [[ "$skip_tls" != "true" ]]; then
    create_service_cert "$CA_DIR" "console.nfr.lab" "$SUBNET.2"
  fi

# Add the console to docker-compose
name="console_$SESSION_ID"
{
  svc_hostname="console.nfr.lab"
  echo "  console:"
  echo "    image: unspecific/victim-v1-tiny:1.3"
  echo "    container_name: $name"
  echo "    hostname: console.nfr.lab"
  echo "    networks:"
  echo "      $NETWORK:"
  echo "        ipv4_address: $SUBNET.2"
  echo "    command: sh -c \"rsyslogd && dnsmasq -k\""
  echo "    environment:"
  if [[ "$skip_tls" != "true" ]]; then
    echo "      - SSL_CERT_PATH=/etc/certs/$svc_hostname/$svc_hostname.crt"
    echo "      - SSL_KEY_PATH=/etc/certs/$svc_hostname/$svc_hostname.key"
  fi
  # now ot add te volumes
  echo "    volumes:"
  if [[ "$skip_tls" != "true" ]]; then
    echo "      - $SESSION_DIR/$CONF_DIR/certs/$svc_hostname/$svc_hostname.crt:/etc/certs/$svc_hostname/$svc_hostname.crt:ro"
    echo "      - $SESSION_DIR/$CONF_DIR/certs/$svc_hostname/$svc_hostname.key:/etc/certs/$svc_hostname/$svc_hostname.key:ro"
  fi
  echo "      - ${SESSION_DIR}/${CONF_DIR}/rsyslog.conf:/etc/rsyslog.conf:ro"
  echo "      - ${SESSION_DIR}/${CONF_DIR}/dnsmasq.conf:/etc/dnsmasq.conf:ro"
  echo "      - ${SESSION_DIR}/${CONF_DIR}/nfr.lab.zone:/etc/nfr.lab.zone:ro"
  echo "      - ${SYSLOG_FILE}:/var/log/containers:rw"
  echo "      - ${SESSION_DIR}/${TARGET_DIR}:/opt/target:rw"
  echo "    expose:"
  echo "      - \"514/udp\""
  echo "      - \"53/udp\""
  echo "      - \"514/tcp\""
  echo "      - \"53/tcp\""
  echo "    restart: unless-stopped"
} >> "$SESSION_DIR/$COMPOSE_FILE"
echo "$name" >> "$SESSION_DIR/services.map"

# Loop through services
declare -i lab_launch=0
svc_count=1
log silent "Time to prepare the victims"
for svc in $(printf "%s\n" "${!services[@]}" | shuf); do
  ((lab_launch++))
  log silent "Initialize the service setup"
  rand_ip=$(get_random_ip)
  svc_hostname=$(get_unique_hostname)
  echo "$rand_ip    $svc_hostname" >> "$ZONEFILE"
  echo "$svc,$svc_hostname" >> "$SESSION_DIR/hostnames.map"
######################################################################
# if TLS is used
  if [[ "$skip_tls" != "true" ]]; then
    create_service_cert "$CA_DIR" "$svc_hostname" "$rand_ip"
  fi
#
######################################################################
  flag=$(generate_flag)
  name="${svc}_host_${SESSION_ID}"
  image=$(get_image_for_service "$svc")
  IFS=' ' read -ra ports <<< "${services[$svc]}"
  for port_proto in "${ports[@]}"; do
    proto=$(cut -d':' -f1 <<< "$port_proto")
    port=$(cut -d':' -f2 <<< "$port_proto")
    tls=$(cut -d':' -f2 <<< "$port_proto")
    log silent " ➕  Enabling $svc on $rand_ip → $proto/$port | Flag: $flag"
    echo " ➕  Enabling Serice port #$svc_count"
    echo "hostname= service= target= port= proto= flag=" >> "$SCORE_CARD"
    ((svc_count++))
  done
  
  # Update the services.map
  echo "$name" >> "$SESSION_DIR/services.map"

  # we will generate a new username and password combination for each service.
  SESS_USER=$(get_vuser)
  SESS_PASS=$(get_vpass)
  SESS_COMMUNITY=$(get_vcommunity)

  # Write to docker-compose.yml with proper indentation
  {
    echo "  $svc:"
    echo "    image: $image"
    echo "    container_name: $name"
    echo "    hostname: $svc_hostname"
    echo "    networks:"
    echo "      $NETWORK:"
    echo "        ipv4_address: $rand_ip"
    echo "    expose:"
    for port_proto in "${ports[@]}"; do
      proto=$(cut -d':' -f1 <<< "$port_proto")
      port=$(cut -d':' -f2 <<< "$port_proto")
      echo "      - \"$port/$proto\""
    done
    # Add environment variables.  Easier to pass all of them to ever servce and let the launch_target script figure it out
    echo "    environment:"
    echo "      - HOSTNAME=$HOSTNAME"
    echo "      - USERNAME=$SESS_USER"
    echo "      - PASSWORD=$SESS_PASS"
    echo "      - COMMUNITY=$SESS_COMMUNITY"
    echo "      - FLAG=$flag"
    echo "      - SERVICE=$svc"
    echo "      - PORTS=$ports"
    if [[ "$skip_tls" != "true" ]]; then
      echo "      - SSL_CERT_PATH=/etc/certs/$svc_hostname/$svc_hostname.crt"
      echo "      - SSL_KEY_PATH=/etc/certs/$svc_hostname/$svc_hostname.key"
    fi
    # now ot add te volumes
    echo "    volumes:"
    if [[ "$skip_tls" != "true" ]]; then
      echo "      - $SESSION_DIR/$CONF_DIR/certs/$svc_hostname/$svc_hostname.crt:/etc/certs/$svc_hostname/$svc_hostname.crt:ro"
      echo "      - $SESSION_DIR/$CONF_DIR/certs/$svc_hostname/$svc_hostname.key:/etc/certs/$svc_hostname/$svc_hostname.key:ro"
    fi
    echo "      - ${SESSION_DIR}/${TARGET_DIR}:/opt/target"

    echo "    logging:"
    echo "      driver: syslog"
    echo "      options:"
    echo "        syslog-address: \"udp://${SUBNET}.2:514\"  # Your lab’s syslog server"
    echo "        tag: \"{{.Name}}\""
    echo "        syslog-format: rfc5424"
 
  } >> "$SESSION_DIR/$COMPOSE_FILE"

  # Record service-specific mapping (IP, Port, Flag)
  for port_proto in "${ports[@]}"; do
    proto=$(cut -d':' -f1 <<< "$port_proto")
    port=$(cut -d':' -f2 <<< "$port_proto")
    echo "$svc: Hostname=$svc_hostname IP=$rand_ip Port=$port Proto=$proto Flag=$flag" >> "$SESSION_DIR/mapping.txt"
  done
  if (( NUM_SERVICES > 0 && lab_launch >= NUM_SERVICES )); then
    # echo "$NUM_SERVICES Launched"
    break
  fi

done


# Add network section to the end of docker-compose.yml
cat >> "$SESSION_DIR/$COMPOSE_FILE" <<EOF
networks:
  ${NETWORK}:
     ipam:
        config:
        - subnet: ${SUBNET}.0/24
          gateway: ${SUBNET}.254
EOF
log silent " Finished Creaeting ${SESSION_DIR}/${COMPOSE_FILE} "


((svc_count--))

REAL_USER="${SUDO_USER:-$USER}"
chown "$REAL_USER:$REAL_USER" "$SCORE_CARD"


if [[ $DO_NOT_RUN ]]; then
  log silent " 🏁 DO NOT RUN MODE"
  log console " 🏁  Confiured $lab_launch targets with $svc_count open ports"
  log console " ⛔️  Dry run is complete."
  log console " 🧠  You can start the docker containers with the following command"
  log console "   \`docker compose -f \"${SESSION_DIR}/${COMPOSE_FILE}\" up -d\`"
  echo
  exit;
else 
  log console " 🚀  Launching $lab_launch targets with $svc_count open ports. Good Luck"
fi

# Launch the containers using docker-compose
docker compose -f "$SESSION_DIR/$COMPOSE_FILE" up -d

# Log running containers
log silent "✅ Final container map:"
DOCKER_PS=$(docker ps --format "table {{.Names}}\t{{.Ports}}")
log console "$DOCKER_PS"

log console "Your Firing Range has been launched."
echo

duration=$SECONDS
log console " ⏱️  Lab launched in $duration seconds"
echo