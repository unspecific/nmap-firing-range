#!/bin/bash

set -e

echo "📦 Updating system and installing dependencies..."
sudo apt update
sudo apt install -y \
  ca-certificates \
  curl \
  gnupg \
  lsb-release \
  bash \
  net-tools \
  coreutils

echo "🔐 Adding Docker GPG key..."
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
  sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

echo "📚 Adding Docker repo..."
echo \
  "deb [arch=$(dpkg --print-architecture) \
  signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

echo "🐳 Installing Docker Engine and Compose Plugin..."
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin || true

# Fallback for systems where compose plugin is missing
if ! command -v docker-compose &>/dev/null && ! docker compose version &>/dev/null; then
  echo "🛠 Installing standalone Docker Compose binary..."
  sudo curl -L "https://github.com/docker/compose/releases/download/v2.24.5/docker-compose-$(uname -s)-$(uname -m)" \
    -o /usr/local/bin/docker-compose
  sudo chmod +x /usr/local/bin/docker-compose
fi

echo "👤 Adding current user to the 'docker' group..."
sudo usermod -aG docker $USER

echo "🌐 Creating Docker network 'pentest-net'..."
docker network create --subnet=192.168.100.0/24 pentest-net || true

echo "📄 Creating docker-compose.yml..."
cat > docker-compose.yml <<EOF
version: '3'
services:
  http:
    image: nginx
    container_name: http_host
    networks:
      pentest-net:
        ipv4_address: 192.168.100.10
    expose: ["80"]

  ssh:
    image: rastasheep/ubuntu-sshd:18.04
    container_name: ssh_host
    networks:
      pentest-net:
        ipv4_address: 192.168.100.11
    expose: ["22"]

  ftp:
    image: stilliard/pure-ftpd:hardened
    container_name: ftp_host
    networks:
      pentest-net:
        ipv4_address: 192.168.100.12
    expose: ["21"]

  smb:
    image: dperson/samba
    container_name: smb_host
    command: "-s 'public;/mnt;yes;no;no;all;none'"
    networks:
      pentest-net:
        ipv4_address: 192.168.100.13
    expose: ["445"]

  telnet:
    image: alpine
    container_name: telnet_host
    command: sh -c "apk add --no-cache busybox-extras && telnetd -F -l /bin/sh"
    networks:
      pentest-net:
        ipv4_address: 192.168.100.14
    expose: ["23"]

  netcat:
    image: alpine
    container_name: netcat_host
    command: sh -c "apk add --no-cache netcat-openbsd && nc -lk -p 9999 -e /bin/cat"
    networks:
      pentest-net:
        ipv4_address: 192.168.100.15
    expose: ["9999"]

networks:
  pentest-net:
    external: true
EOF

echo "⚙️ Creating launch_random_lab.sh script..."
cat > launch_random_lab.sh <<'EOS'
#!/bin/bash

MIN_PORT=2000
MAX_PORT=65000

declare -A services=(
  ["http"]=80
  ["ssh"]=22
  ["ftp"]=21
  ["smb"]=445
  ["telnet"]=23
  ["netcat"]=9999
)

mkdir -p logs
LOGFILE="logs/lab_$(date +%s).log"

echo "🚀 Launching random lab..." | tee $LOGFILE

for svc in "${!services[@]}"; do
  if (( RANDOM % 2 )); then
    port=$(( RANDOM % (MAX_PORT - MIN_PORT + 1) + MIN_PORT ))
    echo "➡️  Starting $svc on port $port (internal: ${services[$svc]})" | tee -a $LOGFILE
    docker compose up -d $svc
    docker container update --publish-add $port:${services[$svc]} ${svc}_host
  else
    echo "❌ Skipping $svc" | tee -a $LOGFILE
  fi
done

echo -e "\n✅ Lab up. Use this to scan:" | tee -a $LOGFILE
docker ps --format "table {{.Names}}\t{{.Ports}}" | tee -a $LOGFILE
EOS

chmod +x launch_random_lab.sh

echo -e "\n✅ All set! Run this to start your first lab:\n"
echo "   ./launch_random_lab.sh"
echo -e "\n🔁 Log out and back in or run: \`newgrp docker\` to use Docker as your user."

