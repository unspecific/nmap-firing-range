#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# ─── Metadata ───────────────────────────────────────────────────────────────
EM_PORT="tcp:1080 tcp:1443:tls"
EM_VERSION="2.4"
EM_DAEMON="FakeSOCKS4"
EM_DESC="SOCKS4 proxy with hidden-flag CONNECT"

FLAG="${FLAG:-flag{socks4-unlocked}}"
MAGIC_IP="10.0.0.99"
MAGIC_PORT=31337

# Helpers
send_reply() {
  # args: status_byte, port (2 bytes), ip (4 bytes)
  printf "\x00%s" "$(printf '\\x%02x' "$1")"
  printf '\\x%02x\\x%02x' $((reply_port>>8)) $((reply_port&0xFF))
  # pack ip
  IFS=. read -r a b c d <<<"$reply_ip"
  printf '\\x%02x\\x%02x\\x%02x\\x%02x' $a $b $c $d
}

# Read the full handshake (VN, CD, DSTPORT, DSTIP, USERID\0, [DOMAIN\0])
read_handshake() {
  # VN + CD + PORT(2) + IP(4)
  read -r -n8 hdr
  vn=$(printf '%d' "'${hdr:0:1}")
  cd=$(printf '%d' "'${hdr:1:1}")
  dstport=$(( ( $(printf '%d' "'${hdr:2:1}") << 8 ) + $(printf '%d' "'${hdr:3:1}") ))
  dstip=$(printf '%d.%d.%d.%d' \
    "$(printf '%d' "'${hdr:4:1}")" \
    "$(printf '%d' "'${hdr:5:1}")" \
    "$(printf '%d' "'${hdr:6:1}")" \
    "$(printf '%d' "'${hdr:7:1}")")

  # read null-terminated USERID
  user=""
  while IFS= read -r -n1 ch && [[ "$ch" != $'\0' ]]; do
    user+="$ch"
  done

  # if SOCKS4A (IP starts with 0.0.0.x), read DOMAIN
  domain=""
  if [[ $dstip == 0.0.0.* ]]; then
    while IFS= read -r -n1 ch && [[ "$ch" != $'\0' ]]; do
      domain+="$ch"
    done
  fi
}

# Main proxy loop
echo "$EM_DAEMON/$EM_VERSION ready for CONNECTs"
while read_handshake; do
  echo "[*] SOCKS4: user='$user' cmd=$cd -> $dstip:$dstport ${domain:+($domain)}"

  # Default failure
  reply_cd=0x5B   # request rejected or failed
  reply_ip="0.0.0.0"
  reply_port=0

  if (( cd == 1 )); then
    # CONNECT
    if [[ "$dstip" == "$MAGIC_IP" && $dstport -eq $MAGIC_PORT ]]; then
      # magic: deliver flag
      reply_cd=0x5A     # request granted
      reply_ip="$dstip"; reply_port=$dstport
      send_reply $reply_cd
      echo -e "\n$FLAG"
      break
    else
      # grant the CONNECT but act as an echo server
      reply_cd=0x5A
      reply_ip="$dstip"; reply_port=$dstport
      send_reply $reply_cd

      # echo loop
      while IFS= read -r data; do
        printf "%b" "$data"
      done
      break
    fi
  fi

  # BIND (cd == 2) or others fall through to rejection
  send_reply $reply_cd
  break
done

sleep 1
