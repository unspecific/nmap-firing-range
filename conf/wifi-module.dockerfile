FROM alpine:3.18

LABEL maintainer="lheath@unspecific.com"
LABEL version="1.0"
LABEL description="WiFi AP + IKEv2 VPN access module for nmap firing range"

# Install required packages.
# iproute2   — ip addr / ip link (interface config)
# hostapd    — WiFi AP management (AP_ENABLED mode)
# dnsmasq    — DHCP for WiFi clients (AP_ENABLED mode)
# strongswan — IKEv2 VPN server (VPN_ENABLED mode)
# iptables   — MASQUERADE NAT so VPN clients can reach lab network
# thttpd     — Landing page served to WiFi/LAN clients
RUN apk update && apk add --no-cache \
    bash iproute2 iptables hostapd dnsmasq strongswan thttpd

# Create working directories
RUN mkdir -p /opt/wifi-module/web/cgi-bin /etc/hostapd /var/log/wifi-module

# Bake in the entrypoint (infrastructure config, not session-specific)
COPY wifi-module-entrypoint.sh /opt/wifi-module/entrypoint.sh
RUN chmod +x /opt/wifi-module/entrypoint.sh

WORKDIR /opt/wifi-module

CMD ["/opt/wifi-module/entrypoint.sh"]
