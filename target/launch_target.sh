#!/bin/bash
logger "Launching launch_target on $HOSTNAME"
echo "------------- New host $HOSTNMAE" >> /opt/target/ENV
env >> /opt/target/ENV

VERSION=1.3

# ─── Input Variables ───────────────────────────────────────────────────────────
SERVICE="${SERVICE}"
FLAG="${FLAG}"
PORT="${PORT:-default}"
USERNAME="${USERNAME:-user}"
PASSWORD="${PASSWORD:-pass}"

logger "🏁 Launching target service: $SERVICE"

trap "echo '🧹 Cleaning up service: $SERVICE'; exit 0" SIGINT SIGTERM

# ─── Launch Routines ───────────────────────────────────────────────────────────

launch_console(){
  echo "Launching Console Apps"
  tcpdump -i any -n > /var/log/tcpdump &
  thttpd -dd /opt/web -c "/cgi-bin/*" -D & 
  ncat --listen --ssl --ssl-cert $SSL_CERT_PATH --ssl-key $SSL_KEY_PATH --sh-exec "ncat 127.0.0.1 80" -k -p 443 &
  rsyslogd
  dnsmasq -k
}


launch_ssh() {
  echo "$FLAG" > /etc/motd
  setup-user -a -f "Victim $USERNAME" -g admin $USERNAME
  echo "$USERNAME:$PASSWORD" | chpasswd
  ssh-keygen -A
  /usr/sbin/sshd -f /opt/target/.ssh/sshd_config -D
}

launch_smb() {
  mkdir -p /srv/samba/share
  echo "$FLAG" > /srv/samba/share/flag.txt
  adduser -D "$USER"
  echo -e "$PASS\n$PASS" | smbpasswd -a -s "$USER"
  smbd -F
}

launch_tftp() {
  echo "$FLAG" > /srv/tftp/flag.txt
  /usr/sbin/in.tftpd --foreground --secure /srv/tftp
}

launch_emulator() {
  local proto="${SERVICE%-em}"
  if [[ -x /opt/target/service_emulator_v2.sh ]]; then
    /opt/target/service_emulator_v2.sh "$proto" "$FLAG" &
    sleep infinity
  else
    logger "❌ Emulator script missing or not executable."
    exit 1
  fi
}

launch_generic() {
  echo "❌ Unknown service: $SERVICE"
  exit 1
}

# ─── Dispatcher ────────────────────────────────────────────────────────────────

case "$SERVICE" in
  console)  launch_console ;;
  ssh)      launch_ssh ;;
  smb)      launch_smb ;;
  tftp)     launch_tftp ;;
  *-em)     launch_emulator ;;
  *)        launch_generic ;;
esac

sleep infinity