#!/bin/bash
# ─── Emulator Metadata ─────────────────────────────────────────────────────
EM_PORT="9999"               # The port this service listens on
EM_VERSION="1.1"               # Optional version identifier
EM_DESC="Custom interface"  # Short description for listing output
EM_DAEMON="Unspecific SOCKS4"

# Read first 8 bytes: VN, CD, DSTPORT, DSTIP
read -r -n 8 handshake

# Convert to hex for parsing
hex=$(echo -n "$handshake" | xxd -p)

# Parse values (VN, CD, PORT, IP)
vn_hex=${hex:0:2}
cd_hex=${hex:2:2}
port_hex=${hex:4:4}
ip_hex=${hex:8:8}

# Optional logging
echo "[*] VN: $vn_hex, CD: $cd_hex, PORT: $port_hex, IP: $ip_hex"

# Fake success response
# SOCKS4 Response: 0x00 0x5A + 2 bytes port + 4 bytes IP
# We'll just mirror back the received port and IP

response=$(echo -n "$hex" | sed 's/^\(..\)\(..\)\(....\)\(........\)/00 5a \3 \4/')

# Convert hex response to binary
echo "$response" | xxd -r -p

# Inject flag after the handshake (as printable junk)
echo -ne "\nflag{socks4-bash-handshake}\n"
