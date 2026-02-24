#!/bin/bash
set -euo pipefail

LOG_DIR="/var/log/wifi-module"
mkdir -p "$LOG_DIR"

log() {
  local msg="$*"
  local ts="[$(date '+%Y-%m-%d %H:%M:%S')]"
  echo -e "$ts [wifi-module] $msg" | tee -a "$LOG_DIR/wifi-module.log"
}

die() {
  log " ❌  $*"
  exit 1
}

# ─── Signal handler ────────────────────────────────────────────────────────────
cleanup() {
  log "🧹 Shutting down wifi-module..."

  if [[ "${VPN_ENABLED:-false}" == "true" ]]; then
    ipsec stop 2>/dev/null || true
  fi

  if [[ "${AP_ENABLED:-false}" == "true" ]]; then
    killall hostapd 2>/dev/null || true
    killall dnsmasq  2>/dev/null || true
    # Release the AP IP we assigned
    ip addr del "${AP_IP:-10.13.37.1}/24" dev "${AP_IFACE:-}" 2>/dev/null || true
  fi

  killall thttpd 2>/dev/null || true

  log "Shutdown complete."
  exit 0
}

trap cleanup SIGTERM SIGINT

# ─── Defaults ─────────────────────────────────────────────────────────────────
AP_ENABLED="${AP_ENABLED:-false}"
VPN_ENABLED="${VPN_ENABLED:-false}"

# ─── Validate required env vars ───────────────────────────────────────────────
if [[ "$AP_ENABLED" == "true" ]]; then
  [[ -n "${AP_IFACE:-}"   ]] || die "AP_IFACE is required when AP_ENABLED=true"
  [[ -n "${AP_PASS:-}"    ]] || die "AP_PASS is required when AP_ENABLED=true"
  AP_SSID="${AP_SSID:-nfr-lab}"
  AP_IP="${AP_IP:-10.13.37.1}"
  AP_CHANNEL="${AP_CHANNEL:-6}"

  # Validate passphrase: 8–63 printable ASCII characters
  local_pass="$AP_PASS"
  if [[ ${#local_pass} -lt 8 || ${#local_pass} -gt 63 ]]; then
    die "AP_PASS must be 8–63 characters (got ${#local_pass})"
  fi
  if [[ "$local_pass" =~ [^[:print:]] ]]; then
    die "AP_PASS contains non-printable characters"
  fi
fi

if [[ "$VPN_ENABLED" == "true" ]]; then
  [[ -n "${VPN_ENDPOINT:-}" ]] || die "VPN_ENDPOINT is required when VPN_ENABLED=true"
  [[ -n "${VPN_PSK:-}"      ]] || die "VPN_PSK is required when VPN_ENABLED=true"
  [[ -n "${VPN_SUBNET:-}"   ]] || die "VPN_SUBNET is required when VPN_ENABLED=true"
  VPN_CLIENT_POOL="${VPN_CLIENT_POOL:-10.99.0.0/24}"
  VPN_DNS="${VPN_DNS:-}"
fi

if [[ "$AP_ENABLED" != "true" && "$VPN_ENABLED" != "true" ]]; then
  log " ⚠️  Neither AP_ENABLED nor VPN_ENABLED is set. Starting landing page only."
fi

# ─── WiFi AP setup ────────────────────────────────────────────────────────────
if [[ "$AP_ENABLED" == "true" ]]; then
  log "Setting up WiFi AP: iface=$AP_IFACE  ssid=$AP_SSID  channel=$AP_CHANNEL"

  # Assign the AP IP to the interface (flush first in case of leftover state)
  ip addr flush dev "$AP_IFACE" 2>/dev/null || true
  ip addr add "${AP_IP}/24" dev "$AP_IFACE"
  ip link set "$AP_IFACE" up

  # Generate hostapd config
  cat > /etc/hostapd/hostapd.conf <<EOF
interface=${AP_IFACE}
ssid=${AP_SSID}
hw_mode=g
channel=${AP_CHANNEL}
wpa=2
wpa_passphrase=${AP_PASS}
wpa_key_mgmt=WPA-PSK
wpa_pairwise=CCMP
rsn_pairwise=CCMP
EOF

  # Generate dnsmasq config for AP clients.
  # No dhcp-option=3 — no default gateway pushed. Natural containment: clients
  # can only reach the AP IP without a VPN tunnel.
  cat > /etc/dnsmasq-ap.conf <<EOF
interface=${AP_IFACE}
bind-interfaces
no-resolv
dhcp-range=10.13.37.10,10.13.37.100,1h
dhcp-option=6,${AP_IP}
EOF

  log "Starting hostapd..."
  hostapd /etc/hostapd/hostapd.conf &
  sleep 1

  log "Starting dnsmasq (AP DHCP)..."
  dnsmasq --conf-file=/etc/dnsmasq-ap.conf &
fi

# ─── IKEv2 VPN setup ──────────────────────────────────────────────────────────
if [[ "$VPN_ENABLED" == "true" ]]; then
  log "Setting up IKEv2 VPN: endpoint=$VPN_ENDPOINT  subnet=$VPN_SUBNET"

  # Build the rightdns line only when VPN_DNS is set
  right_dns_line=""
  [[ -n "$VPN_DNS" ]] && right_dns_line="  rightdns=${VPN_DNS}"

  cat > /etc/ipsec.conf <<EOF
config setup
  charondebug="ike 1, knl 0, cfg 0"

conn %default
  keyexchange=ikev2
  authby=psk
  auto=add

conn nfr-vpn
  left=${VPN_ENDPOINT}
  leftid=@nfr-vpn
  leftsubnet=${VPN_SUBNET}
  right=%any
  rightid=%any
  rightsourceip=${VPN_CLIENT_POOL}
${right_dns_line}
EOF

  cat > /etc/ipsec.secrets <<EOF
: PSK "${VPN_PSK}"
EOF
  chmod 600 /etc/ipsec.secrets

  # MASQUERADE: VPN client traffic (10.99.x.x) appears to originate from
  # this container's lab network IP, so lab container responses route back
  # through here rather than to an unknown next-hop.
  iptables -t nat -A POSTROUTING -s "${VPN_CLIENT_POOL}" -j MASQUERADE 2>/dev/null || \
    log " ⚠️  iptables MASQUERADE rule failed — VPN client routing may not work"

  log "Starting strongSwan..."
  ipsec start
  sleep 2
fi

# ─── Web server (VPN credentials page, AP mode only) ─────────────────────────
# vpn.html + vpn_info.cgi are volume-mounted into /opt/wifi-module/web at launch.
# In VPN-only mode (-N), the console container serves vpn.html on the LAN instead.
if [[ "$AP_ENABLED" == "true" ]]; then
  log "Starting thttpd (VPN page on ${AP_IP}:80)..."
  thttpd -h "${AP_IP}" -p 80 -d /opt/wifi-module/web -c '/cgi-bin/*' -D &
fi

log "✅ wifi-module ready"

# ─── Stay alive — wait for all background jobs ────────────────────────────────
# If any managed process exits unexpectedly, the container exits and Docker
# restarts it (restart: unless-stopped in compose).
wait
