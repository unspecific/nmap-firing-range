#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# ─── Emulator Metadata ─────────────────────────────────────────────────────
EM_PORT="tcp:3389 tcp:1443:tls"
EM_VERSION="10.0"
EM_DAEMON="FakeRDPd"
EM_DESC="Minimal RDP handshake + flag drop"

FLAG="${FLAG:-flag{rdp-session-unlocked}}"

# helper to send a hex string as binary
hex2bin() { echo -n "$1" | xxd -r -p; }

# TPKT/X.224 Connect-Confirm (06 bytes total):
#   03 00 00 06    ← TPKT header (ver=3, reserved, length=6)
#   02 F0 80       ← X.224 CC (CR=2, PDU type=0xF0, Flags=0x80)
CONNECT_CONFIRM="0300000602f080"

# A second “channel join” stub (just another small PDU)
CHANNEL_JOIN="0300000602f080"

echo "$EM_DAEMON/$EM_VERSION ready"

# 1) read client’s initial TPKT (we don’t really parse)
read -r -n4 hdr

# 2) reply with a valid TPKT/X.224 Connect-Confirm
hex2bin "$CONNECT_CONFIRM"

# 3) client will send its MCS Connect-Initial (we’ll just consume it)
#    it’s variable length, but always starts with a TPKT header:
read -r -n4 hdr2
# consume the rest of the packet (length from bytes 3–4)
len=$(( ( $(printf '%d' "'${hdr2:2:1}") << 8 ) + $(printf '%d' "'${hdr2:3:1}") - 4 ))
read -r -n "$len" junk

# 4) send another stub to simulate channel join/setting up the session
hex2bin "$CHANNEL_JOIN"

# 5) now “you’re in the session”—just drop the flag on the wire
#    real clients won’t parse it, but your wrapper can capture it
echo -ne "\r\n*** Here is your RDP session flag: $FLAG ***\r\n"

# give scanners a moment
sleep 1
