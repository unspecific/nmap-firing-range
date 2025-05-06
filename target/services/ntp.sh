#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# ─── Emulator Metadata ─────────────────────────────────────────────────────
EM_PORT="udp:123"                
EM_VERSION="4.2.8"               
EM_DAEMON="FakeNTPd"             
EM_DESC="NTP emulator with TIME & MONLIST"  

HOST=$(hostname)
FLAG="${FLAG:-flag{ntp-echoed-flag}}"

# NTP epoch offset (Unix → NTP)
NTP_OFFSET=2208988800

# Startup banner (so TCP scanners see something on 123/tcp too)
echo "$EM_DAEMON/$EM_VERSION starting on $HOST (UDP/tcp port 123)"

while IFS= read -r line || [[ -n "$line" ]]; do
  cmd=${line%% *}; arg=${line#* }

  case "${cmd^^}" in
    VERSION)
      # Return the fake NTP version
      echo "$EM_DAEMON $EM_VERSION"
      ;;
    TIME)
      # Unix time + NTP offset
      now=$(date +%s)
      ntp_time=$(( now + NTP_OFFSET ))
      echo "TIME $ntp_time"
      ;;
    MONLIST)
      # Fake list of clients; include the flag as one entry
      echo "MONLIST count=4"
      echo "192.0.2.10"  
      echo "198.51.100.5"
      echo "203.0.113.2"
      echo "#FLAG: $FLAG"
      echo "END"
      ;;
    MODE)
      echo "MODE server"
      ;;
    QUIT|EXIT)
      echo "BYE"
      break
      ;;
    *)
      echo "ERROR Unknown command: $cmd"
      ;;
  esac
done

# give any scanner a moment to grab the last reply
sleep 1
