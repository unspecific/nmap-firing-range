#!/bin/bash

APP="Nmap Firing Range (NFR) Launcher"
VERSION=0.5
MIN_PORT=2000
MAX_PORT=65000
SUBNET="192.168.200"
USED_IPS=()
USED_PORTS=()
NUM_SERVICES=5
LAB_DIR="/opt/firing-range"
YAML_DIR="yaml_backup"
FTP_DIR="ftp_flag"
WEB_DIR="web_flag"
LOG_DIR="logs"
TELNET_DIR="telnet_flag"
SMB_DIR="smb_flag"
NC_DIR="nc_flag"
TELNET_LOGIN="telnet_login.sh"
SESSION_ID=$(openssl rand -hex 16)

NCPORT=$(shuf -i1024-9999 -n1)
# 🚨
echo
echo " 🎩  $APP v$VERSION - Lee 'MadHat' Heath <lheath@unspecific.com>"

declare -A services=(
  ["http"]="tcp:80"
  ["ssh"]="tcp:22"
  ["ftp"]="tcp:21"
  ["smb"]="tcp:139 tcp:445 udp:137 udp:138"
  ["telnet"]="tcp:23"
  ["netcat"]="tcp:$NCPORT"
)


# Check dependancies
check_dependencies() {
  local missing=0

  # Required commands
  for cmd in docker rand awk grep sed tee realpath openssl; do
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
  if ! docker network ls | grep -q 'pentest-net'; then
    echo " ℹ️   Docker network 'pentest-net' not found. It will be created by the script."
  fi

  # Check for Docker Compose (V2 or V1 fallback)
  if ! docker compose version &>/dev/null; then
    echo " ❌  'docker compose' is not available. Please install Docker Compose V2."
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
    last_octet=$(( RANDOM % 254 + 2 ))
    ip="$SUBNET.$last_octet"
    if [[ ! " ${USED_IPS[*]} " =~ $ip ]]; then
      USED_IPS+=("$ip")
      echo "$ip"
      return
    fi
  done
}

get_random_port() {
  while :; do
    port=$(( RANDOM % (MAX_PORT - MIN_PORT + 1) + MIN_PORT ))
    if [[ ! " ${USED_PORTS[*]} " =~ $port ]]; then
      USED_PORTS+=("$port")
      echo "$port"
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
    telnet|netcat) echo "alpine" ;;
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
    netcat)
      echo "sh -c 'apk add --no-cache netcat-openbsd && echo \\\"$flag\\\" > /banner && while true; do nc -lk -p $NCPORT -e /bin/cat < /banner; done'"  # Netcat command directly
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

while getopts "n:hd" opt; do
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
    *)
      echo "Invalid option. Use -h for help."
      exit 1
      ;;
  esac
done

# Prepare session folder
SESSION_TIME=$(date +"%Y-%m-%d_%H-%M-%S")
SESSION_DIR="$LAB_DIR/$LOG_DIR/lab_$SESSION_ID"
mkdir -p "$SESSION_DIR"
LOGFILE="$SESSION_DIR/lab.log"
COMPOSE_FILE="docker-compose.yml"

echo " 🚀  Launching random lab at $SESSION_TIME" | tee "$LOGFILE"

echo " 🆔  SESSION_ID $SESSION_ID" | tee "$LOGFILE"

check_dependencies

echo " 🌐  Creating Subnet for Scanning - ${SUBNET}.0/24 - DockerID:"

# Create network if needed
docker network inspect pentest-net >/dev/null 2>&1 || \
  docker network create --subnet=$SUBNET.0/24 pentest-net

if [[ -f "$LAB_DIR/$COMPOSE_FILE" ]]; then
  mkdir -p "$LAB_DIR/$YAML_DIR"
  mv "$LAB_DIR/$COMPOSE_FILE" "$LAB_DIR/$YAML_DIR/${COMPOSE_FILE}_backup_$(date +%s)"
fi

# Start docker-compose.yml
echo "# Auto-generated docker-compose.yml (${APP}-v$VERSION) - $(date)" > "$LAB_DIR/$COMPOSE_FILE"
echo "# SESSION_ID: $SESSION_ID" >> "$LAB_DIR/$COMPOSE_FILE"
echo "services:" >> "$LAB_DIR/$COMPOSE_FILE"

# Loop through services
declare -i lab_launch=0
svc_count=1
for svc in $(printf "%s\n" "${!services[@]}" | shuf); do
  ((lab_launch++))
  rand_ip=$(get_random_ip)
  int_port=${services[$svc]}
  flag=$(generate_flag)
  name="${svc}_host"
  image=$(get_image_for_service "$svc")
  command_block=$(get_command_for_service "$svc" "$flag")
  IFS=' ' read -ra ports <<< "${services[$svc]}"
  for port_proto in "${ports[@]}"; do
    proto=$(cut -d':' -f1 <<< "$port_proto")
    port=$(cut -d':' -f2 <<< "$port_proto")
    echo " ➕  Enabling $svc on $rand_ip → $proto/$port | Flag: $flag" >> "$LOGFILE"
    echo " ➕  Enabling Serice port #$svc_count"
    ((svc_count++))
  done

  # Handle HTTP special case
  if [[ "$svc" == "http" ]]; then
    mkdir -p "$LAB_DIR/$WEB_DIR"
    echo "<html><body><h1>Welcome to $svc</h1><p>$flag</p></body></html>" > $LAB_DIR/$WEB_DIR/index.html
  fi

  if [[ "$svc" == "ftp" ]]; then
    mkdir -p "$LAB_DIR/$FTP_DIR"
    echo "$flag" > "$LAB_DIR/$FTP_DIR/flag.txt"
    echo "README - nothing to see here" > "$LAB_DIR/$FTP_DIR/README.txt"
    echo "Welcome to backup server" > "$LAB_DIR/$FTP_DIR/welcome.txt"
  fi

  if [[ "$svc" == "smb" ]]; then
    mkdir -p "$LAB_DIR/$SMB_DIR"
  fi

  if [[ "$svc" == "telnet" ]]; then
    mkdir -p "$LAB_DIR/$TELNET_DIR"

    # Generate the login script for Telnet
    cat > "$LAB_DIR/$TELNET_DIR/$TELNET_LOGIN" <<EOF
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
    chmod +x "$LAB_DIR/$TELNET_DIR/$TELNET_LOGIN"
  fi

  # Write to docker-compose.yml with proper indentation
  {
    echo "  $svc:"
    echo "    image: $image"
    echo "    container_name: $name"
    echo "    networks:"
    echo "      pentest-net:"
    echo "        ipv4_address: $rand_ip"
    echo "    expose:"
    for port_proto in "${ports[@]}"; do
      proto=$(cut -d':' -f1 <<< "$port_proto")
      port=$(cut -d':' -f2 <<< "$port_proto")
      echo "      - \"$port/$proto\""
    done

    if [[ "$svc" == "ftp" ]]; then
      echo "    volumes:"
      echo "      - $LAB_DIR/$FTP_DIR:/data/ftpuser"
      echo "    environment:"
      echo "      - PUBLICHOST=127.0.0.1"
      echo "      - FTP_USER_NAME=ftpuser"
      echo "      - FTP_USER_PASS=ftpuser"
      echo "      - FTP_USER_HOME=/data/ftpuser"
      echo "      - ADDED_FLAGS=-d -d"
      # echo "    command: \"/run.sh -d\""
    elif [[ "$svc" == "telnet" ]]; then
      echo "    volumes:"
      echo "      - $LAB_DIR/$TELNET_DIR/$TELNET_LOGIN:/fake_login.sh:ro"
    elif [[ -n "$command_block" ]]; then
      echo "    command: \"$command_block\""
    fi
  } >> "$LAB_DIR/$COMPOSE_FILE"

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

# Add network section to the end of docker-compose.yml
cat >> "$LAB_DIR/$COMPOSE_FILE" <<EOF
networks:
  pentest-net:
    external: true
EOF

((svc_count--))


if [[ $DO_NOT_RUN ]]; then
  echo " 🏁  Confiured $lab_launch targets with $svc_count open ports"
  echo " ⛔️  Dry run is complete."
  echo " 🧠  You can start the docker containers with the following command"
  echo "   \`docker compose -f "$LAB_DIR/$COMPOSE_FILE" up -d\`"
  echo
  exit;
else 
  echo " 🚀  Launching $lab_launch targets with $svc_count open ports. Good Luck"
fi

# Launch the containers using docker-compose
docker compose -f "$LAB_DIR/$COMPOSE_FILE" up -d

# Log running containers
echo -e "\n✅ Final container map:" >> "$LOGFILE"
docker ps --format "table {{.Names}}\t{{.Ports}}" >> "$LOGFILE"

echo "Your Firing Range has been launched."
echo