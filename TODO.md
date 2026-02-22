# TODO

## VPN Access (L2TP/IPSec + PSK)

Goal: Let CTF players connect from their own machines (Windows/Mac/Linux/mobile) using
the native VPN client — no app install required. PSK auth is fine for a CTF.

### Container
- Image: `libreswan` or `xl2tpd` + `strongswan` in the existing Alpine victim image,
  OR a dedicated container (`hwdsl2/ipsec-vpn-server` is a well-known pre-built option)
- Needs: `NET_ADMIN`, `SYS_MODULE` caps; `/dev/ppp` device; kernel modules `af_key`, `xfrm_user`
- Static IP on the lab network (e.g. `.1` of the session /24)
- Routes the lab /24 back to connected clients

### launch_lab.sh changes
- Add `-W` / `--vpn` flag to optionally launch the VPN container
- Add `-E <ip>` / `--endpoint <ip>` flag for the host IP clients will connect to
  (auto-detect with `ip route get 1` as default, override for public/remote use)
- During setup:
  - Generate a random PSK (or accept via flag)
  - Generate a random VPN username + password (or accept via flags)
  - Write credentials to session dir and to console web root as `vpn.txt`
  - Add VPN container to docker-compose output
- Print connection info at end of launch output

### Console web dashboard changes
- `index.html`: Add "VPN Access" panel showing:
  - Server IP / endpoint
  - PSK
  - Username / Password
  - Per-OS connection instructions (Windows / macOS / Linux)
- Or serve a `vpn.html` page and link from the dashboard nav

### Connection details to display per OS
- **Windows**: Settings → VPN → Add VPN → Type: L2TP/IPSec with PSK
- **macOS**: System Settings → VPN → Add VPN → L2TP over IPSec
- **Linux**: `nmcli` one-liner or NetworkManager GUI
- **iOS/Android**: Built-in VPN settings → L2TP

### Ports to expose on host
- UDP 500  (IKE)
- UDP 4500 (IPSec NAT-T)
- UDP 1701 (L2TP) — only needs to be reachable inside the tunnel, not always exposed

## Other

- Custom service banners (README still marked TBD)
- score_card.cgi reset should be player-scoped (currently wipes all players' scores)
- cleanup_lab needs a --help output
