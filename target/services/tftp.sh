#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# ─── Emulator Metadata ─────────────────────────────────────────────────────
EM_PORT="udp:69"                      
EM_VERSION="0.1"                      
EM_DAEMON="FakeTFTPd"                 
EM_DESC="TFTP emulator – get flag.txt" 

# Config
BLOCKSIZE=512
FLAGFILE="flag.txt"
FLAG_CONTENT="${FLAG:-flag{tftp-retrieved-flag}}"

# Banner
echo "$EM_DAEMON/$EM_VERSION ready for TFTP RRQ"

# State
expecting_ack=0

while IFS= read -r line || [[ -n "$line" ]]; do
  # parse command + args
  cmd=$(echo "$line"  | awk '{print toupper($1)}')
  args="${line#* }"

  case "$cmd" in
    RRQ)
      # Usage: RRQ <filename> <mode>
      fname=$(echo "$args" | awk '{print $1}')
      mode=$(echo "$args"  | awk '{print toupper($2)}')
      if [[ $mode != "OCTET" ]]; then
        echo "ERROR 0 Unsupported transfer mode: $mode"
        break
      fi

      if [[ $fname == "$FLAGFILE" ]]; then
        # Send first (and only) DATA block
        block=1
        data="$FLAG_CONTENT"
        echo "DATA $block $data"
        expecting_ack=$block
      else
        echo "ERROR 1 File not found: $fname"
        break
      fi
      ;;

    ACK)
      # Usage: ACK <block#>
      blk=$(echo "$args" | awk '{print $1}')
      if (( blk == expecting_ack )); then
        # final block was < BLOCKSIZE, so transfer done
        echo "# Transfer of block $blk complete"
        break
      else
        echo "ERROR 0 Unexpected ACK $blk"
        break
      fi
      ;;

    WRQ)
      echo "ERROR 2 Write requests not allowed"
      break
      ;;

    *) 
      echo "ERROR 4 Illegal TFTP operation: $cmd"
      break
      ;;
  esac
done

# Give any scanner a moment to grab the final packet
sleep 1
