# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

---

## [Unreleased]

### Added
- `conf/web_score_card/cgi-bin/leaderboard.cgi`: New bash CGI that aggregates `score.json` by player, sums scores, counts submissions, and returns ranked JSON — powers the live leaderboard
- `conf/web_score_card/leaderboard.html`: New full-screen live leaderboard page with gold/silver/bronze rank styling, blinking LIVE badge, "YOU" indicator for the current player, and 5-second auto-refresh
- `TODO.md`: Project TODO list

### Changed
- `conf/web_score_card/cgi-bin/submit_score.cgi`: Now accepts and stores a `player` field (operator callsign) in each `score.json` entry for per-player tracking
- `conf/web_score_card/index.html`: Redesigned as a CTF competition dashboard — CTF-style header, operator callsign overlay on first visit, live mini leaderboard panel (top 5, 10-second refresh), Quick Reference panel, and nav link to Leaderboard
- `conf/web_score_card/scorecard.html`: Redesigned for multi-player use — operator callsign registration, displays current player's callsign, filters submissions to show only the current player's entries, sends `player` field on form submit

### Changed
- `target/services/`: Added `read -t` timeouts to all 26 service emulator scripts to prevent containers from hanging indefinitely on idle or abandoned connections
  - 30-second timeout on interactive command loops (SSH, FTP, Telnet, IMAP, POP3, SMTP, MySQL, PostgreSQL, Redis, LDAP, Memcached, RabbitMQ, HTTP, API, IRC, NNTP, NTP, TFTP, DNS, CRAP, SMB)
  - 10-second timeout on binary protocol handshakes (RDP, VNC, SOCKS4, SNMP, Finger)

### Fixed
- `target/services/telnet.sh`, `imap.sh`, `pop3.sh`, `nntp.sh`, `ftp.sh`: Fixed `(( attempts++ ))` without `|| :` under `set -e` — the post-increment returned the old value (0) as the expression result, causing the script to exit immediately on the very first failed login attempt
- `target/services/api.sh`: Fixed copy-paste bug where `pass` was set from `BASH_REMATCH[1]` (the username capture group) instead of `BASH_REMATCH[2]` (the password capture group) — login only worked when username and password were identical
- `target/services/snmp.sh`: Fixed `handle_getnext()` silently treating an unrecognized OID as index 0 and returning the wrong entry; now returns `SNMP Error: noSuchName` as expected
- `bin/launch_lab.sh`: Fixed shebang (`#!/bin/bash` → `#!/usr/bin/env bash`) to match all other scripts
- `bin/launch_lab.sh`: Fixed variable name typo `$SCORECARD` → `$SCORE_CARD` on score card log line (was silently expanding to empty string)
- `bin/check_lab.sh`: Added `set -euo pipefail`; fixed all arithmetic increment/decrement expressions to be safe under `set -e` (`(( n++ )) || :`)
- `bin/muck_data.sh`: Added `set -euo pipefail`; guarded `$1`/`$2` references with `${1:-}` and `:?` error messages
- README: Corrected ~20 typos and grammatical errors throughout (lst→list, GitHib→GitHub, authenitcation→authentication, workhose→workhorse, reitterate→reiterate, INSTAL_DIR→INSTALL_DIR, lab_sesion_id→lab_session_id, and others)
- README: Restored mangled TLS sentence ("Each session,LS support is disabled" → "Each session, unless SSL support is disabled")
- `target/launch_target.sh`: Fixed path typo `/opt/tatget/` → `/opt/target/` in `launch_smb()`
- `target/launch_target.sh`: Fixed inverted `sed` error-check logic in `launch_snmp()` — error messages were firing on success instead of failure
- `target/launch_target.sh`: Fixed copy-paste error messages for SESSION_ID and PORT substitutions in `launch_snmp()`
- `target/services/`: Made 10 service scripts executable that were missing the execute bit (`dns.sh`, `mysql.sh`, `ntp.sh`, `postgres.sh`, `rabbitmq.sh`, `rdp.sh`, `smb.sh`, `ssh.sh`, `tftp.sh`, `vnc.sh`)

---

## [2.2.9] - Active development

### Added
- AI-assisted development pass (commit ec634db)
- Console UI for web-based scoring
- DNS forward and reverse (PTR) records via dnsmasq
- TLS/SSL support for services that support encrypted ports
- Service emulators for DNS, NTP, MySQL, PostgreSQL, Redis, Memcached, RabbitMQ, LDAP, NNTP, IRC, SOCKS4, RDP, VNC, Finger, API, CRAP

### Known Issues / TBD
- Custom service banner randomization not yet implemented
- Full web dashboard / log visualization not yet implemented
- `make push` (Docker registry) not yet configured
- Not all emulated services are fully functional (ongoing)
- `cleanup_lab` is missing a `--help` output

---

## [2.2.x] - Earlier development

### Added
- Core `launch_lab.sh` orchestration: randomized IPs, hostnames, credentials, flags, TLS cert generation
- Session replay via `launch_lab -i SESSION_ID`
- Scoring engine (`check_lab.sh`)
- Cleanup (`cleanup_lab.sh`)
- Setup/install script (`setup_lab.sh`) with GitHub and local install modes, rollback support
- Docker Compose file generation per session
- Per-session Certificate Authority and signed host certificates
- Centralized syslog server (rsyslog) on console container
- DNS environment (dnsmasq) with forward and reverse records
- Web scoring interface (partial) served from console container
- 27 service emulators in `target/services/`
- Alpine and Debian Docker image variants (`victim-v1-tiny`, `victim-v1-large`, `victim-v2-gui`, `victim-v2-smgui`)
- Randomization dictionaries: hostnames, usernames, passwords, SNMP communities
