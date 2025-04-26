#!/bin/bash

VERSION=1.2

# ─── Input Variables ───────────────────────────────────────────────────────────
SERVICE="${TARGET_SERVICE}"
FLAG="${TARGET_FLAG}"
PORT="${TARGET_PORT:-default}"
USERNAME="${TARGET_USER:-user}"
PASSWORD="${TARGET_PASS:-pass}"

echo "🏁 Launching target service: $SERVICE"
export SERVICE FLAG PORT USERNAME PASSWORD

trap "echo '🧹 Cleaning up service: $SERVICE'; exit 0" SIGINT SIGTERM

# ─── Launch Routines ───────────────────────────────────────────────────────────

add_user() {
  setup-user -a -f "Victim $USERNAME" -g admin $USERNAME
  # setup-user [-h] [-a] [-u] [-f FULLNAME] [-g GROUPS] [-k SSHKEY] [USERNAME]
}

launch_ssh() {
  echo "$FLAG" > /etc/motd
  echo "root:$PASS" | chpasswd
  service ssh start
  tail -f /dev/null
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
  if [[ -x /opt/target/service_emulator.sh ]]; then
    /opt/target/service_emulator.sh "$proto" "$FLAG"
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

tail -f /dev/null