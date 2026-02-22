# TODO

## Multi-user / WiFi CTF Mode (In Progress — Design Complete)

See full design: `~/.claude/projects/.../memory/vpn-wifi-plan.md`

### Access modes
- Solo (default): local only, single user, no admin password
- `-M` Multi-user: WebUI bound to LAN IP, admin password, routing hints + warning
- `-N` Network VPN: `-M` + `fr-wifi-module` in VPN-only mode (strongSwan on LAN IP)
- `-A [iface]` WiFi AP: forces `-M` + `-N`, full `fr-wifi-module` (hostapd + dnsmasq + strongSwan)
- `-K <pass>` Override WiFi password (only valid with `-A`)

### launch_lab.sh
- [ ] Remove `-W` / hwdsl2 block entirely (never used/tested — lines ~944-967, ~1211-1245, ~1315-1328)
- [ ] Remove `-E` flag (no longer needed)
- [ ] Add `-M` / `-N` / `-A [iface]` / `-K <pass>` flag parsing + usage docs
- [ ] Add implication logic: `-A` forces `-M` + `-N`; `-N` implies `-M`
- [ ] Pre-flight checks (run before session setup, exit cleanly on conflict):
  - `-M`: port 80 free on LAN IP
  - `-N`/`-A`: UDP 500 + 4500 free on target IP; `net.ipv4.ip_forward=1` already set
  - `-A`: 10.13.37.1 not assigned to any interface; WiFi interface detection (see plan)
- [ ] `-K` validation: 8–63 printable ASCII chars, reject otherwise with clear error
- [ ] Generate `ipsec.conf` + `ipsec.secrets` per session when VPN enabled
- [ ] Update `vpn.txt` format: IKEv2 PSK only (no username/password)
- [ ] Console compose block: bind port 80 to LAN IP when `-M`; to 10.13.37.1 when `-A`
- [ ] Add `fr-wifi-module` compose block:
  - `-N` only: standard Docker network, `cap_add: NET_ADMIN`, port-bound to LAN IP
  - `-A`: `network_mode: host`, `privileged: true`, full AP env vars
- [ ] Update launch messages per mode (routing hints, VPN creds, WiFi SSID/pass)
- [ ] Browser auto-open (check `$DISPLAY`/`$XAUTHORITY`, open as `$SUDO_USER`)

### New container: `fr-wifi-module` (our own Alpine build)
- [ ] `conf/wifi-module.dockerfile` — Alpine + hostapd + dnsmasq + strongswan + thttpd
- [ ] `conf/wifi-module-entrypoint.sh`:
  - If `AP_ENABLED=true`: generate hostapd.conf + dnsmasq.conf, start AP services
  - If `VPN_ENABLED=true`: generate ipsec.conf + ipsec.secrets, start strongSwan
  - Always start thttpd (landing page / redirect to console WebUI)
  - SIGTERM handler: graceful shutdown of all services
  - DHCP: 10.13.37.10–100, NO default gateway (natural containment)
  - Channel: configurable via `AP_CHANNEL`, default 6 (2.4GHz)
- [ ] Add Makefile targets: `build-wifi-module`, `package-wifi-module`, `load-wifi-module`
- [ ] Build + package as `fr-wifi-module-1.0.tar.gz` for offline distribution

### Web dashboard
- [ ] `vpn.html`: replace L2TP instructions with IKEv2 per-OS steps
- [ ] `vpn.html`: remove username/password fields
- [ ] Admin password gate (deferred to WebUI phase — see below)

### cleanup_lab.sh
- [ ] `fr-wifi-module` stopped by `docker compose down` — verify no extra cleanup needed


## WebUI Improvements

### Admin / lab access token (tied to `-M` mode)
- [ ] Solo mode: no password gate
- [ ] `-M` mode: generate token at launch, print to console, mount into console container
- [ ] JS gate in index.html reads token from URL fragment (#token=xxx) or sessionStorage

### Help page
- [ ] `conf/web_score_card/help.html` — nmap CLI examples, per-service hints, wordlist links
- [ ] Add nav link in index.html

### Wordlists served through WebUI
- [ ] Generate `$SESSION_DIR/wordlist.txt` at launch (session creds + dict padding)
- [ ] Mount into console container, serve as static file or CGI
- [ ] Link from help.html

### Scorecard
- [ ] `score_card.cgi` reset should be player-scoped (currently wipes all players)


## Content / Data

### Wordlist expansion
- [ ] `conf/dicts/vusers.conf` — expand from 20 to ~100 entries
- [ ] `conf/dicts/vpasswds.conf` — review quality (currently 55 entries)

### Custom service banners
- [ ] README still says TBD — implement randomized banners per service
