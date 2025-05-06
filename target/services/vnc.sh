#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# ─── Emulator Metadata ─────────────────────────────────────────────────────
EM_PORT="tcp:5900 tcp:5901:tls"
EM_VERSION="003.008"
EM_DAEMON="FakeVNCd"
EM_DESC="Minimal RFB 3.8 handshake + flag via clipboard"

FLAG="${FLAG:-flag{vnc-clipboard-flag}}"

hexdump_send() {
  # send a hex string (spaces optional) as binary
  echo "$1" | xxd -r -p
}

# 1) ProtocolVersion
echo -ne "RFB $EM_VERSION\n"

# 2) Read client version (12 bytes)
IFS= read -r -N12 client_ver || exit

# 3) Security handshake: we only support “None” (type 1)
echo -ne "\x01\x01"    # [number of types=1][type=1]
IFS= read -r -N1 _     # client picks type

# 4) SecurityResult OK
echo -ne "\x00\x00\x00\x00"

# 5) ServerInit
#    width=80 (0x0050), height=24 (0x0018)
printf '\x00\x50\x00\x18'

#    PixelFormat (16 bytes):
#      bpp=32, depth=24, bigEndian=0, trueColor=1
#      redMax=0x00ff, greenMax=0x00ff, blueMax=0x00ff
#      redShift=16, greenShift=8, blueShift=0, padding=3 bytes
pf_bytes=(0x20 0x18 0x00 0x01 0x00 0xff 0x00 0xff 0x00 0xff 0x10 0x08 0x00 0x00 0x00 0x00)
for b in "${pf_bytes[@]}"; do
  printf "\\x%02x" $b
done

#    Desktop name
name="FakeVNCd"
namelen=${#name}
# 4-byte big-endian name length
printf "\\x%02x\\x%02x\\x%02x\\x%02x" \
  $((namelen>>24&0xff)) $((namelen>>16&0xff)) \
  $((namelen>>8&0xff))   $((namelen&0xff))
echo -n "$name"

# 6) Read ClientInit (1 byte: sharedFlag)
IFS= read -r -N1 _ || exit

# 7) Send a ServerCutText (clipboard) message with the flag
#    MsgType=3, pad[3]=0, length[4], then text
flaglen=${#FLAG}
# header
printf '\x03\x00\x00\x00'
# length (4-byte BE)
printf "\\x%02x\\x%02x\\x%02x\\x%02x" \
  $((flaglen>>24&0xff)) $((flaglen>>16&0xff)) \
  $((flaglen>>8&0xff))   $((flaglen&0xff))
# payload
echo -n "$FLAG"

# 8) Done—sleep so scanners can pick it up
sleep 1
