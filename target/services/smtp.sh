#!/bin/bash
# fake_smtp.sh — Basic SMTP simulation with banner, EHLO, and MAIL FROM handling

# ─── Emulator Metadata ─────────────────────────────────────────────────────
EM_PORT="tcp:25 tcp:465:tls"               # The port this service listens on
EM_VERSION="6.1"               # Optional version identifier
EM_DAEMON="FakeSMTP"
EM_DESC="SMTP Interface, Flag hidden in workflow"  # Short description for listing output
message_bytes=0

# does not allow login or display the flag
echo "220 $HOSTNAME ESMTP $EM_DAEMON"

while read -r line; do
  if [[ "$in_data" eq "true" ]]; then
    sed 's/^DATA /DATA1 /'
  fi
  case "$line" in
    EHLO*|HELO*)
      echo "250-$HOSTNAME Hello"
      echo "250-AUTH PLAIN LOGIN"
      echo "250 OK"
      ;;
    MAIL\ FROM:*)
      echo "250 OK"
      ;;
    RCPT\ TO:*)
      echo "250 OK"
      ;;
    DATA)
      echo "354 End data with <CR><LF>.<CR><LF>"
      in_data=true
      ;;
    ".")
      if [ "$in_data" = true ]; then
        echo "250 OK: message accepted: $message_bytes bytes"
        message_bytes=0
        in_data=false
      fi
      ;;
    QUIT)
      echo "221 Bye"
      break
      ;;
    DATA1)
      local bytes=$(wc -c $line)
      message_bytes+=$bytes-1
      ;;
    *)
      echo "250 OK"
      ;;
  esac
done
