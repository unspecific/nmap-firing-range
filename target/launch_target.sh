#!/bin/bash
logger "Launching launch_target on $HOSTNAME"
echo "------------- New host $HOSTNMAE" >> /opt/target/ENV
env >> /opt/target/ENV

VERSION=1.2

# ─── Input Variables ───────────────────────────────────────────────────────────
SERVICE="${TARGET_SERVICE}"
FLAG="${TARGET_FLAG}"
PORT="${TARGET_PORT:-default}"
USERNAME="${TARGET_USER:-user}"
PASSWORD="${TARGET_PASS:-pass}"

logger "🏁 Launching target service: $SERVICE"
export SERVICE FLAG PORT USERNAME PASSWORD

trap "echo '🧹 Cleaning up service: $SERVICE'; exit 0" SIGINT SIGTERM

# ─── Launch Routines ───────────────────────────────────────────────────────────

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
    /opt/target/service_emulator_v2.sh "$proto" "$FLAG"
  else
    echo "❌ Emulator script missing or not executable."
    exit 1
  fi
}

launch_generic() {
  echo "❌ Unknown service: $SERVICE"
  exit 1
}

# ─── Dispatcher ────────────────────────────────────────────────────────────────

case "$SERVICE" in
  ssh)      launch_ssh ;;
  smb)      launch_smb ;;
  tftp)     launch_tftp ;;
  *-em)     launch_emulator ;;
  *)        launch_generic ;;
esac

bash