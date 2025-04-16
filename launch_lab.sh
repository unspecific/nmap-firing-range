#!/bin/bash

# If it's not root, sudo 
if [[ $EUID -ne 0 ]]; then
  echo "🔒 Root access required. Re-running with sudo..."
  exec sudo "$0" "$@"
fi

APP="Nmap Firing Range (NFR) Launcher"
VERSION=0.7.5
THRD_OCT=$(shuf -i2-254 -n1)
SUBNET="192.168.$THRD_OCT"
USED_IPS=()
USED_PORTS=()
NUM_SERVICES=5
LAB_DIR="/opt/firing-range"
BIN_DIR="bin"
FTP_DIR="ftp_flag"
WEB_DIR="web_flag"
LOG_DIR="logs"
TELNET_DIR="telnet_flag"
SMB_DIR="smb_flag"
NC_DIR="nc_flag"
TELNET_LOGIN="telnet_login.sh"
SESSION_ID=$(openssl rand -hex 16)
NCPORT=$(shuf -i1024-9999 -n1)
SECONDS=0

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
  if ! docker network ls | grep -q $NETWORK; then
    echo " ℹ️   Docker network $NETWORK not found. It will be created by the script."
  fi

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


get_random_ip() {
  while :; do
    last_octet=$(shuf -i2-254 -n1)
    ip="$SUBNET.$last_octet"
    if [[ ! " ${USED_IPS[*]} " =~ $ip ]]; then
      USED_IPS+=("$ip")
      echo "$ip"
      return
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
    http)
      echo ""  # No specific command for HTTP, as Nginx will start by default
      ;;
    *) echo "" ;;
  esac
}

declare -A services=(
  ["http"]="tcp:80"
  ["ssh"]="tcp:22"
  ["ftp"]="tcp:21"
  ["smb"]="tcp:139 tcp:445 udp:137 udp:138"
  ["telnet"]="tcp:23"
  ["other"]="tcp:$NCPORT"
)

while getopts "n:hdVi:" opt; do
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
      echo "to scan with nmap and use it's scipts to find the flags"
      echo "The hosts with me in the ${SUBNET}.0\24 subnet" 
      echo
      echo "Usage: $0 [-d][-n number_of_services]"
      echo
      echo "-d  Do not run.  This i a dry run.  No Docker containers started"
      echo "-n <num_services>  Start # of services/hosts"
      echo
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

if [[ -n "${REPLAY_SESSION_ID:-}" ]]; then
  SESSION_DIR="/opt/firing-range/logs/lab_$REPLAY_SESSION_ID"
  COMPOSE_FILE="$SESSION_DIR/docker-compose.yml"

  echo "🔁 Replaying session $REPLAY_SESSION_ID..."

  if [[ ! -f "$COMPOSE_FILE" ]]; then
    echo "❌ docker-compose.yml not found in $SESSION_DIR"
    exit 1
  fi
  echo " 🚀  Launching Replay of Session $REPLAY_SESSION_ID" | tee -a "$LOGFILE"
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


echo " 🎩  $APP v$VERSION - Lee 'MadHat' Heath <lheath@unspecific.com>" > $LOGFILE
echo " 🚀  Launching random lab at $SESSION_TIME" | tee -a "$LOGFILE"
echo " 🆔  SESSION_ID $SESSION_ID" | tee -a "$LOGFILE"
echo "# 🎩 Nmap Firing Range ScoreCard - Lee 'MadHat' Heath <lheath@unspecific.com>" > $SCORE_CARD
echo "#    Started on $HOSTNAME at $SESSION_TIME" >> $SCORE_CARD 
echo "session=$SESSION_ID" >> $SCORE_CARD
echo "# service=telnet target=${SUBNET}.153 port=5537 proto=tcp flag=FLAG{89ea16740192885a}" >> $SCORE_CARD
echo "# Valid services ftp ssh telnet http smb other" >> $SCORE_CARD
echo " 📊  Score Card Created" | tee -a "$LOGFILE"

check_dependencies

echo " 🌐  Creating Subnet for Scanning - ${SUBNET}.0/24 - $NETWORK" | tee -a "$LOGFILE"
# Create network if needed
docker network inspect $NETWORK >/dev/null 2>&1 || \
  docker network create --subnet=$SUBNET.0/24 $NETWORK

# Start docker-compose.yml
echo "# Auto-generated docker-compose.yml (${APP}-v$VERSION) - $(date)" > "$SESSION_DIR/$COMPOSE_FILE"
echo "# SESSION_ID: $SESSION_ID" >> "$SESSION_DIR/$COMPOSE_FILE"
echo "services:" >> "$SESSION_DIR/$COMPOSE_FILE"
echo " ➕  Created docker-compose.yaml" >> "$LOGFILE"

echo "# Auto-generated docker-compose.yml (${APP}-v$VERSION) - $(date)" > "$SESSION_DIR/services.map"
echo "# Services file for sesion $SESSION_ID" >> "$SESSION_DIR/services.map"
echo " ➕  Created services.map" >> "$LOGFILE"

# Loop through services
declare -i lab_launch=0
svc_count=1
for svc in $(printf "%s\n" "${!services[@]}" | shuf); do
  ((lab_launch++))
  rand_ip=$(get_random_ip)
  int_port=${services[$svc]}
  flag=$(generate_flag)
  name="${svc}_host_${SESSION_ID}"
  image=$(get_image_for_service "$svc")
  command_block=$(get_command_for_service "$svc" "$flag")
  IFS=' ' read -ra ports <<< "${services[$svc]}"
  for port_proto in "${ports[@]}"; do
    proto=$(cut -d':' -f1 <<< "$port_proto")
    port=$(cut -d':' -f2 <<< "$port_proto")
    echo " ➕  Enabling $svc on $rand_ip → $proto/$port | Flag: $flag" >> "$LOGFILE"
    echo " ➕  Enabling Serice port #$svc_count"
    echo "service= target= port= proto= flag=" >> $SCORE_CARD
    ((svc_count++))
  done
  
  # Update the services.map
  echo "$name" >> "$SESSION_DIR/services.map"

  # Handle HTTP special case
  if [[ "$svc" == "http" ]]; then
    echo " ➕  Creating $WEB_DIR assets" >> "$LOGFILE"
    mkdir -p "$SESSION_DIR/$WEB_DIR"
    echo "<html><body><h1>Welcome to $svc</h1><p>$flag</p></body></html>" > $SESSION_DIR/$WEB_DIR/index.html
  fi

  if [[ "$svc" == "ftp" ]]; then
    echo " ➕  Creating $FTP_DIR assets" >> "$LOGFILE"
    mkdir -p "$SESSION_DIR/$FTP_DIR"
    echo "$flag" > "$SESSION_DIR/$FTP_DIR/flag.txt"
    echo "README - nothing to see here" > "$SESSION_DIR/$FTP_DIR/README.txt"
    echo "Welcome to backup server" > "$SESSION_DIR/$FTP_DIR/welcome.txt"
  fi

  if [[ "$svc" == "smb" ]]; then
    echo " ➕  Creating $SMB_DIR assets" >> "$LOGFILE"
    mkdir -p "$SESSION_DIR/$SMB_DIR"
  fi

  if [[ "$svc" == "telnet" ]]; then
    echo " ➕  Creating $TELNET_DIR assets" >> "$LOGFILE"
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
    echo "    networks:"
    echo "      $NETWORK:"
    echo "        ipv4_address: $rand_ip"
    echo "    expose:"
    for port_proto in "${ports[@]}"; do
      proto=$(cut -d':' -f1 <<< "$port_proto")
      port=$(cut -d':' -f2 <<< "$port_proto")
      echo "      - \"$port/$proto\""
    done

    if [[ "$svc" == "ftp" ]]; then
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
    elif [[ -n "$command_block" ]]; then
      echo "    command: \"$command_block\""
    fi
  } >> "$SESSION_DIR/$COMPOSE_FILE"

  # Record service-specific mapping (IP, Port, Flag)
  for port_proto in "${ports[@]}"; do
    proto=$(cut -d':' -f1 <<< "$port_proto")
    port=$(cut -d':' -f2 <<< "$port_proto")
    echo "$svc: IP=$rand_ip Port=$port Proto=$proto Flag=$flag" >> "$SESSION_DIR/mapping.txt"
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
    external: true
EOF
echo " ➕  Finished Creaeting $COMPOSE_FILE " >> "$LOGFILE"


((svc_count--))


if [[ $DO_NOT_RUN ]]; then
  echo " 🏁 DO NOT RUN MODE" >> "$LOGFILE"
  echo " 🏁  Confiured $lab_launch targets with $svc_count open ports" | tee -a "$LOGFILE"
  echo " ⛔️  Dry run is complete." | tee -a "$LOGFILE"
  echo " 🧠  You can start the docker containers with the following command"
  echo "   \`docker compose -f "$SESSION_DIR/$COMPOSE_FILE" up -d\`"
  echo
  exit;
else 
  echo " 🚀  Launching $lab_launch targets with $svc_count open ports. Good Luck"  | tee -a "$LOGFILE"
fi

# Launch the containers using docker-compose
docker compose -f "$SESSION_DIR/$COMPOSE_FILE" up -d

# Log running containers
echo -e "\n✅ Final container map:" >> "$LOGFILE"
docker ps --format "table {{.Names}}\t{{.Ports}}" >> "$LOGFILE"

echo "Your Firing Range has been launched."
echo

duration=$SECONDS
echo " ⏱️  Lab launched in $duration seconds" | tee -a "$LOGFILE"
