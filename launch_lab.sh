#!/bin/bash

# If it's not root, sudo 
if [[ $EUID -ne 0 ]]; then
  echo "🔒 Root access required. Re-running with sudo..."
  exec sudo "$0" "$@"
fi

### CONFIG ###
APP="Nmap Firing Range (NFR) Launcher"
APP_SHORT="NFR Launcher"
VERSION=2.0
THRD_OCT=$(shuf -i2-254 -n1)
SUBNET="192.168.$THRD_OCT"
USED_IPS=()
NUM_SERVICES=5
LAB_DIR="/opt/firing-range"
BIN_DIR="bin"
FTP_DIR="ftp_flag"
WEB_DIR="web_flag"
LOG_DIR="logs"
TELNET_DIR="telnet_flag"
SMB_DIR="smb_flag"
# NC_DIR="nc_flag"
TELNET_LOGIN="telnet_login.sh"
SESSION_ID=$(openssl rand -hex 4)
NCPORT=$(shuf -i1024-9999 -n1)
SECONDS=0
DOMAIN='.nfr.lab'


### FUNCTIONS ###
log() {
  local mode="$1"
  shift
  local message=$*
  local log
  log="[$(date '+%Y-%m-%d %H:%M:%S')] [$APP_SHORT v$VERSION] $message"

  if [[ "$mode" == "console" ]]; then
    echo "$message"
  fi
  echo "$log" >> "$LOGFILE"
}

#######################################################################
# if the user wants TLS, we first create a CA
#
reate_ca() {
  local ca_dir="$1"  # e.g., "$SESSION_DIR/certs"
  mkdir -p "$ca_dir"

  openssl genrsa -out "$ca_dir/ca.key" 2048
  openssl req -x509 -new -nodes -key "$ca_dir/ca.key" \
    -sha256 -days 365 -out "$ca_dir/ca.crt" \
    -subj "/CN=FiringRange Lab CA"
}

#######################################################################
# we will also create a cert for ech host launched
create_service_cert() {
  local ca_dir="$1"
  local name="$2"        # e.g. ftp_host
  local ip="$3"          # e.g. 192.168.200.101
  local out_dir="$ca_dir/$name"
  mkdir -p "$out_dir"

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

  openssl x509 -req \
    -in "$out_dir/$name.csr" \
    -CA "$ca_dir/ca.crt" -CAkey "$ca_dir/ca.key" -CAcreateserial \
    -out "$out_dir/$name.crt" \
    -days 365 -sha256 \
    -extfile "$out_dir/$name.cnf" -extensions v3_req
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

create_ca() {
  local ca_dir="$1"  # e.g., "$SESSION_DIR/certs"
  mkdir -p "$ca_dir"

  openssl genrsa -out "$ca_dir/ca.key" 2048
  openssl req -x509 -new -nodes -key "$ca_dir/ca.key" \
    -sha256 -days 365 -out "$ca_dir/ca.crt" \
    -subj "/CN=FiringRange Lab CA"
}


get_ruser() {
  local user_file="$LAB_DIR/conf/vusers"

  if [[ ! -f "$user_file" ]]; then
    echo "❌ User file not found: $user_file" >&2
    return 1
  fi

  # Filter out empty or comment lines, then pick a random user
  shuf -n 1 < <(grep -vE '^\s*#|^\s*$' "$user_file")
}

get_rpass() {
  local pass_file="$LAB_DIR/conf/vpasswords"

  if [[ ! -f "$pass_file" ]]; then
    echo "❌ Password file not found: $pass_file" >&2
    return 1
  fi

  # Filter out empty or comment lines, then pick a random password
  shuf -n 1 < <(grep -vE '^\s*#|^\s*$' "$pass_file")
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

load_emulated_services() {
  local services_dir="$LAB_DIR/bin/services"
  local script svc port
  SERVICE_LIST=()

  for script in "$services_dir"/*.sh; do
    [[ -f "$script" ]] || continue

    svc=$(basename "$script" .sh)
    port=$(grep -E '^EM_PORT=' "$script" | cut -d= -f2 | tr -d '"')

    if [[ -n "$port" ]]; then
      services["${svc}-em"]="tcp:$port"
      SERVICE_LIST+=("$svc")
      log console "✔️  Loaded emulator: ${svc}-em on tcp:$port"
    else
      log console "⚠️  Skipping emulator: $svc (missing EM_PORT)"
    fi
  done
}


get_image_for_service() {
  case $1 in
    http) echo "nginx" ;;
    ssh) echo "rastasheep/ubuntu-sshd:18.04" ;;
    ftp) echo "stilliard/pure-ftpd:hardened" ;;
    smb) echo "dperson/samba" ;;
    dvwa) echo "citizenstig/dvwa" ;; 
    telnet|other) echo "alpine" ;;
    tftp) echo "pghalliday/tftp" ;;
    snmp) echo "leprechaun/snmpd" ;;
    smtp) echo "namshi/smtp" ;;
    imap|pop) echo "tvial/docker-mailserver" ;;
    vnc) echo "dorowu/ubuntu-desktop-lxde-vnc" ;;
  esac
}

get_command_for_service() {
  local service=$1
  local flag="$2"

  case $service in
    smb)
      echo "-s 'public;/mnt;yes;no;no;all;none'"  # SMB command directly
      ;;
    telnet)
      echo "sh -c 'apk add --no-cache busybox-extras && telnetd -F -l $TELNET_LOGIN'"
      ;;
    other)
      echo "sh -c 'apk add --no-cache netcat-openbsd && echo \\\"$flag\\\" > /banner && while true; do cat /banner | nc -lk -p $NCPORT -q 1; done'"  # Netcat command directly
      ;;
    ssh)
      echo "bash -c 'echo \\\"$flag\\\" > /etc/motd && /usr/sbin/sshd -D'"  # SSH command directly    
      ;;
    http|dvwa|smtp|imap|pop|vnc)
      echo ""  # Defaults to image CMD
      ;;
    tftp)
      echo ""
      ;;
    snmp)
      echo ""
      ;;
    *)
      echo ""
     ;;
  esac
}


declare -A services=(
  ["http"]="tcp:80"
  ["ssh"]="tcp:22"
  ["ftp"]="tcp:21"
  ["smb"]="tcp:139 tcp:445 udp:137 udp:138"
  ["telnet"]="tcp:23"
  ["other"]="tcp:$NCPORT"
  ["tftp"]="udp:69"
  ["snmp"]="udp:161"
  ["smtp"]="tcp:25"
  ["imap"]="tcp:143"
  ["pop"]="tcp:110"
  ["vnc"]="tcp:5900"
)



while getopts "ln:hdVi:t" opt; do
  case "$opt" in
    n)
      NUM_SERVICES="$OPTARG"
      ;;
    d)
      DO_NOT_RUN=true
      ;;
    h)
      echo
      echo "$APP v$VERSION by MadHat Unspecific madhat@unspecific.com"
      echo "$APP is a script that will set up a number of target's with flags"
      echo "    to scan with nmap and use it's scipts to find the flags"
      echo
      echo "Usage: $0 [-d][-n number_of_services]"
      echo
      echo "-d  Do not run.  This i a dry run.  No Docker containers started"
      echo "-n <num_services>  Start # of services/hosts. Default: 5"
      echo "-i <SESSION_ID>   to replay the session with that <SESSION_ID>"
      echo "-V   shows the Version of the app and exits"
      echo
      exit 0
      ;;
    l)
      echo
      echo " 🎩  $APP v$VERSION - Lee 'MadHat' Heath <lheath@unspecific.com>"
      echo 
      echo "The following services are supported on this firing range."
      for svc in $(printf "%s\n" "${!services[@]}" | shuf); do
        echo "$svc"
      done
      exit 0
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

# Prepare session folder
SESSION_TIME=$(date +"%Y-%m-%d_%H-%M-%S")
SESSION_DIR="$LAB_DIR/$LOG_DIR/lab_$SESSION_ID"
mkdir -p "$SESSION_DIR"
LOGFILE="$SESSION_DIR/lab.log"
COMPOSE_FILE="docker-compose.yml"
SCORE_CARD="score_card"
HOSTNAME=$(hostname)
NETWORK=range-$SESSION_ID
declare -A USED_HOSTNAMES=()



# CA_DIR="$SESSION_DIR/certs"
# create_ca "$CA_DIR"



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


log silent " 🎩  $APP v$VERSION - Lee 'MadHat' Heath <lheath@unspecific.com>"
log console " 🚀  Launching random lab at $SESSION_TIME"
log console " 🆔  SESSION_ID $SESSION_ID"
{
  echo "# 🎩 Nmap Firing Range ScoreCard - Lee 'MadHat' Heath <lheath@unspecific.com>" 
  echo "#    Started on $HOSTNAME at $SESSION_TIME"
  echo "session=$SESSION_ID"
  echo "# service=telnet target=${SUBNET}.153 port=5537 proto=tcp flag=FLAG{89ea16740192885a}"
  echo "# Valid services ftp ssh telnet http smb other"
} > "$SCORE_CARD"
log console " 📊  Score Card Created"

check_dependencies

log console " 🌐  Creating Subnet for Scanning - ${SUBNET}.0/24 - $NETWORK"
# Create network if needed
# docker network inspect "$NETWORK" >/dev/null 2>&1 || \
#  docker network create --driver bridge --subnet="${SUBNET}.0/24" --gateway="${SUBNET}.254" "$NETWORK"

# Start docker-compose.yml
{
  echo "# Auto-generated docker-compose.yml (${APP}-v$VERSION) - $(date)"
  echo "# SESSION_ID: $SESSION_ID"
  echo "services:"
} > "$SESSION_DIR/$COMPOSE_FILE"
log silent " Created docker-compose.yaml - ${SESSION_DIR}/${COMPOSE_FILE}"

{
  echo "# Auto-generated docker-compose.yml (${APP}-v$VERSION) - $(date)"
  echo "# Services file for sesion $SESSION_ID"
} > "$SESSION_DIR/services.map"
log silent " Created ${SESSION_DIR}/services.map"

# Loop through services
declare -i lab_launch=0
svc_count=1
for svc in $(printf "%s\n" "${!services[@]}" | shuf); do
  ((lab_launch++))
  rand_ip=$(get_random_ip)
  svc_hostname=$(get_unique_hostname)
  echo "$svc,$svc_hostname" >> "$SESSION_DIR/hostnames.map"

######################################################################
# if TLS is used
# HOSTNAME=
# create_service_cert "$CA_DIR" "ftp_host" "192.168.200.101"
# create_service_cert "$CA_DIR" "http_host" "192.168.200.102"
#
######################################################################
  flag=$(generate_flag)
  name="${svc}_host_${SESSION_ID}"
  image=$(get_image_for_service "$svc")
  command_block=$(get_command_for_service "$svc" "$flag")
  IFS=' ' read -ra ports <<< "${services[$svc]}"
  for port_proto in "${ports[@]}"; do
    proto=$(cut -d':' -f1 <<< "$port_proto")
    port=$(cut -d':' -f2 <<< "$port_proto")
    log silent " ➕  Enabling $svc on $rand_ip → $proto/$port | Flag: $flag"
    echo " ➕  Enabling Serice port #$svc_count"
    echo "hostname= service= target= port= proto= flag=" >> "$SCORE_CARD"
    ((svc_count++))
  done
  
  # Update the services.map
  echo "$name" >> "$SESSION_DIR/services.map"

  if [[ "$svc" == "telnet" ]]; then
    log silent " ➕  Creating $TELNET_DIR assets"
    mkdir -p "$SESSION_DIR/$TELNET_DIR"

    # Generate the login script for Telnet
    cat > "$SESSION_DIR/$TELNET_DIR/$TELNET_LOGIN" <<EOF
#!/bin/sh
echo Welcome to Acme Widget Corp
echo -n Login:
read user
echo -n Password:
read pass
if [ "\$user" = "guest" ] && [ "\$pass" = "guest" ]; then
  echo Access granted.
  echo "$flag"
else
  echo Login failed.
  sleep 2
  exit 1
fi
EOF
    chmod +x "$SESSION_DIR/$TELNET_DIR/$TELNET_LOGIN"
  fi

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

    log silent " ➕  Creating $svc assets"
    if [[ "$svc" == "ftp" ]]; then
      mkdir -p "$SESSION_DIR/$FTP_DIR"
      echo "$flag" > "$SESSION_DIR/$FTP_DIR/flag.txt"
      echo "README - nothing to see here" > "$SESSION_DIR/$FTP_DIR/README.txt"
      echo "Welcome to backup server" > "$SESSION_DIR/$FTP_DIR/welcome.txt"

      echo "    volumes:"
      echo "      - $SESSION_DIR/$FTP_DIR:/data/ftpuser"
      echo "    environment:"
      echo "      - PUBLICHOST=127.0.0.1"
      echo "      - FTP_USER_NAME=ftpuser"
      echo "      - FTP_USER_PASS=ftpuser"
      echo "      - FTP_USER_HOME=/data/ftpuser"
      echo "      - ADDED_FLAGS=-d -d"
      # echo "    command: \"/run.sh -d\""
    elif [[ "$svc" == "telnet" ]]; then
      echo "    volumes:"
      echo "      - $SESSION_DIR/$TELNET_DIR/$TELNET_LOGIN:/fake_login.sh:ro"
    elif [[ "$svc" == "tftp" ]]; then
      mkdir -p "$LAB_DIR/tftp_data"
      echo "$flag" > "$LAB_DIR/tftp_data/flag.txt"
      echo "    volumes:"
      echo "      - $LAB_DIR/tftp_data:/tftp"
      echo "    environment:"
      echo "      - PGID=1000"
      echo "      - PUID=1000"
      echo "      - UMASK=022"
    elif [[ "$svc" == "snmp" ]]; then
      mkdir -p "$LAB_DIR/snmp_flag"
      echo "$flag" > "$LAB_DIR/snmp_flag/sysDescr.txt"
      echo "    volumes:"
      echo "      - $LAB_DIR/snmp_flag:/usr/share/snmp"
    elif [[ "$svc" == "vnc" ]]; then
      mkdir -p "$LAB_DIR/vnc_flag"
      echo "$flag" > "$LAB_DIR/vnc_flag/FLAG.txt"
      echo "    environment:"
      echo "      - VNC_PASSWORD=password"
    elif [[ "$svc" == "smtp" ]]; then
      mkdir -p "$LAB_DIR/smtp_flag"
      echo "$flag" > "$LAB_DIR/smtp_flag/email.txt"
      echo "    volumes:"
      echo "      - $LAB_DIR/smtp_flag:/var/mail"
      echo "    environment:"
      echo "      - RELAY_NETWORKS=:0.0.0.0/0"
      echo "      - MAILNAME=firing-range.local"
    elif [[ "$svc" == "smb" ]]; then
      log silent " ➕  Creating $svc assets"
      mkdir -p "$SESSION_DIR/$SMB_DIR"
    elif [[ "$svc" == "http" ]]; then
      mkdir -p "$SESSION_DIR/$WEB_DIR"
      echo "<html><body><h1>Welcome to $svc</h1><p>$flag</p></body></html>" > "${SESSION_DIR}/${WEB_DIR}/index.html"
      echo "    volumes:"
      echo "      - $LAB_DIR/web_content:/usr/share/nginx/html:ro"
    fi
    # For TLS Support.
    #  volumes:
    #  - ./certs/http_host/http_host.crt:/certs/server.crt:ro
    #  - ./certs/http_host/http_host.key:/certs/server.key:ro
    #  echo "    environment:"
    #  echo "      - SSL_CERT_PATH=/certs/server.crt"
    #  echo "      - SSL_KEY_PATH=/certs/server.key"

    if [[ -n "$command_block" ]]; then
      log silent " ➕  Adding Command ${svc} to docker-compose"
      echo "    command: \"$command_block\""
    fi
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

REAL_USER="${SUDO_USER:-$USER}"
chown "$REAL_USER:$REAL_USER" "$SCORE_CARD"

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