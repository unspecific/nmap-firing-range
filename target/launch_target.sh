#!/bin/bash
logger "Launching launch_target on $HOSTNAME"
echo "------------- New host $HOSTNMAE" >> /opt/target/ENV
launch_log="/opt/target/$HOSTNAME.launch_log"
touch "$launch_log"

trap "echo '🧹 Cleaning up service: $SERVICE'; exit 0" SIGINT SIGTERM

log() {
  local message="$1"
  local timestamp="[$(date '+%Y-%m-%d %H:%M:%S')]"
  local logline="$timestamp $message"

  # finally append
  echo "$logline" >> "$launch_log"
}

# ─── Launch Routines ───────────────────────────────────────────────────────────

launch_console(){
  log "Launching Console Apps"
  tcpdump -i any -nn > /var/log/tcpdump &
  thttpd -dd /opt/web -c "/cgi-bin/*" -D & 
  ncat --listen --ssl --ssl-cert $SSL_CERT_PATH --ssl-key $SSL_KEY_PATH --sh-exec "ncat 127.0.0.1 80" -k -p 443 &
  rsyslogd
  dnsmasq -k
}

launch_ssh() {
  log "Launching SSHd"
  echo "$FLAG" > /etc/motd
  setup-user -a -f "Victim $USERNAME" -g admin $USERNAME
  echo "$USERNAME:$PASSWORD" | chpasswd
  ssh-keygen -A
  /usr/sbin/sshd -4 -f /opt/target/conf/ssh/sshd_config -D
}

launch_smb() {
  log "Launching Samba"
  mkdir -p /opt/share
  echo "$FLAG" > /opt/share/flag.txt
  adduser -D "$USERNAME"
  echo -e "$PASSWORD\n$PASSWORD" | smbpasswd -a -s "$USERNAME"
  smbd -l "/var/log/services/" --configfile "/opt/tatget/conf/smb/smb.conf" -F
}

launch_tftp() {
  log "Launching tftp"
  echo "$FLAG" > /opt/target/conf/tftp/.flag
  /usr/sbin/in.tftpd -l -R 4096:32767 -s /opt/target/conf/tftp/
}


launch_http() {
  log "Launching HTTPd"
  HTTP_DIR="/opt/target/conf/http"
  echo "$FLAG" > "$HTTP_DIR/.flag"
  find "$HTTP_DIR" -type f -exec chmod 744 {} \;
  find "$HTTP_DIR" -type d -exec chmod 755 {} \;
  chmod 755 "$HTTP_DIR/cgi-bin/*.cgi"
  # And launch the httpd server
  thttpd -d /opt/target/conf/http -c '/cgi-bin/*'
  ncat --listen --ssl --ssl-cert $SSL_CERT_PATH --ssl-key $SSL_KEY_PATH --sh-exec "ncat 127.0.0.1 80" -k -p 443
}

launch_smtp() {
  log "Launching SMTP"
  smtpd -F
}

launch_snmp() {
  log "Launching SNMP"
  rsyslogd
  SNMP_CONF="/opt/target/conf/snmp/snmpd.conf"
  echo "$FLAG" > "/opt/target/conf/snmp/.flag"
  if [[ ! -f "$SNMP_CONF" ]]; then
    logger "Missing Config SNMP $SNMP_CONF"
    exit 1
  fi
  if sed -i "s/%COMMUNITY%/${COMMUNITY}/g" "$SNMP_CONF"; then
    logger "unable to update community"
  fi
  if sed -i "s/:0.0.0.0:/:${IP_ADDRESS}:/g" "$SNMP_CONF"; then
    logger "unable to update Bind IP"
  fi
  if sed -i "s/%SESSION_ID%/${SESSION_ID}/g" "$SNMP_CONF"; then
    logger "unable to update community"
  fi
  if sed -i "s/%PORT%/${PORTS}/g" "$SNMP_CONF"; then
    logger "unable to update community"
  fi
  snmpd -f -Lsd -c "$SNMP_CONF"
}


launch_emulator() {
  log "Launching Service Emulator"
  local proto="${SERVICE%-em}"
  if [[ -x /opt/target/services/service_emulator.sh ]]; then
    /opt/target/services/service_emulator.sh "$proto" "$FLAG" &
  else
    log " ❌  Emulator script missing or not executable."
    exit 1
  fi
}

launch_generic() {
  log " ❌  Unknown service: $SERVICE"
  exit 1
}

# ─── Dispatcher ────────────────────────────────────────────────────────────────
log "Launching target services"
log $(env)
case "$SERVICE" in
  console)  launch_console ;;
  ssh)      launch_ssh ;;
  smb)      launch_smb ;;
  tftp)     launch_tftp ;;
  ftp)      launch_ftp ;;
  http)     launch_http ;;
  smtp)     launch_smtp ;;
  snmp)     launch_snmp ;;
  *-em)     launch_emulator ;;
  *)        launch_generic ;;
esac

sleep infinity