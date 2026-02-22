
# Nmap Firing Range

## TL;DR

A self-contained, randomized lab for practicing Nmap, recon, and service enumeration.
Each session spins up Docker containers on a unique /24 subnet with random IPs,
hostnames, credentials, and flags — so every run is different.

```bash
# Install (requires internet)
curl -O https://raw.githubusercontent.com/unspecific/nmap-firing-range/main/bin/setup_lab.sh
chmod +x setup_lab.sh && ./setup_lab.sh

# Launch a solo session (5 targets)
launch_lab

# Scan it
nmap -v 192.168.X.0/24 --dns-servers 192.168.X.2

# Open the dashboard
http://console.nfr.lab/

# Clean up
cleanup_lab
```

**Access modes:**

| Command | Who can reach the lab |
|---|---|
| `launch_lab` | Host machine only (default) |
| `launch_lab -M` | Anyone on your LAN (add a static route) |
| `launch_lab -M -N` | Anyone on your LAN via IKEv2 VPN |
| `launch_lab -A [iface]` | WiFi CTF — players connect to your AP, get VPN creds, scan away |

**Requirements:** Docker, `docker compose`, ~100 MB disk (image).
**WiFi mode** (`-A`) additionally needs: a USB WiFi adapter with AP support, `iw`, `net.ipv4.ip_forward=1`.

---

## 🔥 Nmap Firing Range Project

The **Nmap Firing Range** project began organically when one of our employees requested a way to practice using Nmap while studying for an upcoming certification exam. To accelerate development, we leveraged ChatGPT to assist in quickly gathering details about a wide range of network services, protocols, and application behaviors — helping us decrease the research and setup time significantly.

What started as a simple idea has evolved into a flexible, containerized lab environment designed for real-world Nmap practice, reconnaissance training, and service enumeration exercises.

### Key Features

- **Containerized Environment:**  
  Each service is launched in an isolated Docker container, allowing easy resets, scalability, and modularity. Users can spin up individual targets or a full lab environment on demand.

- **Randomized Targets:**  
  Each lab session creates a /24 network in 192.168.0.0/16, and each host has a random IP, ensuring that scans mimic real-world unpredictability. This helps participants move beyond relying on standard ports and easily recognizable service signatures.

- **Service Emulation:**  
  A wide range of classic network services are emulated.  Look [here](nfr-target-services.txt) for the current list.

  These emulated services will fingerprint as the service for nmap, can support brute forcing, and other protocol specific tricks. 

- **TLS/SSL Support:**  
  Many services can optionally be configured to support SSL/TLS, requiring scanners to properly detect and negotiate secure sessions.  Each session, unless SSL support is disabled, generates a new CA for the lab session.  Each host has a unique hostname, and a server certificate signed by the CA.

- **Dynamic Credential Generation:**  
  Each service can receive randomly generated usernames and passwords at launch, preventing users from relying on default credentials and promoting proper enumeration techniques.  This includes snmp communities and other authentication methods to allow for brute forcing.

- **Custom Service Banners: TBD**  
  Banners are randomized at container start to simulate different application versions, operating systems, and server responses, making fingerprinting and enumeration exercises more challenging and authentic.

- **Logging for Scoring and Review**
  Services include logging capabilities to capture user interaction. This enables scoring, post-scan analysis, and training feedback without affecting the live lab environment.

- **DNS and Reverse DNS (PTR)**  
  A full DNS environment is simulated using Dnsmasq, including forward and reverse (PTR) records. This allows students to practice identifying services based on DNS enumeration rather than only IP scanning.

- **Syslog Server Integration:**  
  All container logs are sent to a centralized syslog server, which also acts as the environment’s DNS server. Logs persist across container restarts for full session visibility.

- **CTF Web Dashboard**
  A browser-based dashboard is served from the console container at `http://console.nfr.lab/`. It provides real-time visibility into the session and supports multi-player CTF competitions:
  - **Scorecard** — submit findings (hostname, IP, port, protocol, service, flag) and track your personal score
  - **Leaderboard** — live ranked leaderboard showing all players; auto-refreshes every 5 seconds
  - **Syslog viewer** — real-time streaming log output from all containers with client-side filtering
  - **TCPDump viewer** — live network packet table with per-column filtering
  - **Operator callsign** — each player registers a callsign (stored in browser localStorage) to identify their submissions across a shared session


### Project Goals

- Provide a practical, repeatable environment for Nmap training and service discovery.
- Build muscle memory around real-world scanning, port mapping, banner grabbing, and basic vulnerability identification.
- Teach participants to adjust scanning techniques dynamically when encountering randomized environments.
- Allow easy extension to new services, protocols, and security scenarios for advanced training.

- Make it a game. Multiple players can compete simultaneously via the live leaderboard — run it as a fingerprinting CTF for a class or team.
- The program is extensible.  The emulated service can be dropped into a folder to add more service options.


I have included a [list of available services](./nfr-target-services.txt) to show what services are supported.  As of now not all work 100% of the time.  That is the next task.

I have also included a [sample scan](./sample_scan.txt)

---

# Installation

If you have internet access on the host you want to install the firing range on,
- download the [setup_lab.sh](https://raw.githubusercontent.com/unspecific/nmap-firing-range/refs/heads/main/bin/setup_lab.sh) file.
- chmod 755 setup_lab.sh
- ./setup_lab.sh

This will allow you to install directly from GitHub.

You can also download the package to install on an offline host.
- download the [NFR Zip](https://github.com/unspecific/nmap-firing-range/archive/refs/heads/main.zip)
- unzip the file.  It will create a folder called nmap-firing-range
- cd nmap-firing-range/bin
- chmod 755 setup_lab.sh
- ./setup_lab.sh

During the install it will see the local files and give an option to download or use the local files. 

Once installed, you can use setup_lab to uninstall or update the system

```
$ ./setup_lab.sh --help
🔒 Root access required. Re-running with sudo...

 🎩  NFR-SetupLab v2.2.9 - Lee 'MadHat' Heath <lheath@unspecific.com>

Firing Range Setup Script
Usage: ./bin/setup_lab.sh [OPTIONS]

Options:
  --help, -h            Show this help message and exit
  --uninstall           Uninstall all components and optionally backup logs
  --unattended          Run with no prompts (overwrite defaults)
  --upgrade             Download and install the latest scripts from GitHub
  --force               Overwrite all existing files without prompting
  --install-dir, --prefix DIR
                        Install into DIR instead of the default (/opt/firing-range)

This script installs or upgrades the Firing Range lab, verifies dependencies,
installs shell scripts, sets up permissions, and can pull the latest version
of the scripts from GitHub.
```

Once installed the apps can be called directly as they are added to your path.

- launch_lab - For setup and launching a new lab session
- check_lab - For scoring your findings.  Moving to a web interface on the console server
- cleanup_lab - Removes all the containers, networks, configuration entries used for the lab session

---

launch_lab is the real workhorse of the project and most of what is listed above is covered here.
It does add a group and adds the current user for easier access to the lab files.

launch_lab does relaunch with sudo when setting up a lab, but not a few options, like help and list services.

During the first run it will check to make sure you have docker and the required image installed.  It is ***unspecific/victim-v1-tiny***

It is included with the install package and is 22M compressed and ~78M in action.  If you want to build your own container locally, it is based on Alpine Linux, and in the <conf/> directory is a make file to build it yourself.  We will cover that below.


```
$ launch_lab -h

NFR Launcher v2.2.9 by Lee 'MadHat' Heath <lheath@unspecific.com>

Sets up a containerized lab network for offensive security testing.
Each session is unique (IP, hostnames, services, flags), with optional TLS.

Usage: /usr/local/sbin/launch_lab [options]

Options:
  -n <number>    Number of targets to launch (default: 5)
  -d             Dry run (don't actually start containers)
  -i <session>   Replay an existing session by ID
  -t             Skip TLS/SSL cert generation and encrypted ports
  -p             Skip plain-text (unencrypted) protocols
  -s <service>   Launch only the named service (use -l to list)
  -W             Launch a VPN container (L2TP/IPSec + PSK)
  -E <ip>        Public endpoint IP for VPN clients (auto-detected by default)
  -l             List available services and exit
  -V             Show version and exit
  -h             Show this help message and exit
```

---

check_lab has minimal options.  By default it looks for the score_card in the PWD, and uses that to score against.  You can also specify the specific score_card you want to use.

Once launched, point a browser to `http://console.nfr.lab/` (a `/etc/hosts` entry is added automatically and removed by `cleanup_lab`). The web interface supports multi-player CTF competitions — give participants VPN or SSH access to the lab network and have them compete via the leaderboard.

**Web pages:**

| Page | URL | Description |
|---|---|---|
| Dashboard | `/` | Session info, running containers, live mini-leaderboard |
| Scorecard | `/scorecard.html` | Submit findings; shows your personal score history |
| Leaderboard | `/leaderboard.html` | Live ranked leaderboard for all players |
| Syslog | `/logger.html` | Real-time container log stream |
| TCPDump | `/tcpdump.html` | Live network packet capture viewer |
| VPN Access | `/vpn.html` | VPN credentials and per-OS connection instructions (requires `-W`) |

```
$ check_lab -h

NFR-CheckLab v2.2.9 by Lee 'MadHat' Heath <lheath@unspecific.com>

Scores a completed lab session by comparing your score_card submissions
against the session's ground truth (mapping.txt).  Prints a breakdown of
correct/incorrect answers and lists any services that were not attempted.

Usage: check_lab [OPTIONS] [SCORE_CARD_FILE]

Arguments:
  SCORE_CARD_FILE   Path to the score_card file to score.
                    Defaults to <install_dir>/score_card.

Options:
  --name NAME         Set the player name displayed in the header
                      (written back into the score_card file)
  --help, -h          Show this help message and exit
```

---

The last script in the project is ***cleanup_lab***
It removes all evidence of the lab session except for the lab directory (***/opt/firing-range/*** is the default)

```
$ cleanup_lab --help

NFR Cleanup v2.2.9 by Lee 'MadHat' Heath <lheath@unspecific.com>

Tears down a running lab session: stops and removes containers, networks,
and volumes, removes /etc/hosts entries, and backs up the score card.

Usage: cleanup_lab [OPTIONS] [score_card_file]

Arguments:
  score_card_file   Path to the score_card for the session to clean up.
                    Defaults to ./score_card in the current directory.

Options:
  --help, -h        Show this help message and exit
```

It looks for ***./score_card*** to use the session ID for cleanup, or you can call it with a specific score_card file.

---

As mentioned in the <conf/> directory (Default install location is ***/opt/firing-range/conf/***) there is a Makefile.  This is used to build and manage the Docker images used.  The only one used today is ***victim-v1-tiny***

As of this time the images are not added to docker hub.

```
$ make help
🛠️  Nmap Firing Range 🫥 - Docker Image Toolkit

Build Targets:
  make build-v1-tiny       Build Alpine-based victim image
  make build-v1-large      Build Debian-based victim image
  make build-v2-gui        Build Debian desktop GUI victim image
  make build-v2-smgui      Build Alpine desktop GUI victim image
  make build-all           Build all victim images

Package Targets:
  make package-v1-tiny     Export + gzip v1-tiny image
  make package-v1-large    Export + gzip v1-large image
  make package-v2-gui      Export + gzip v2-gui image
  make package-v2-smgui    Export + gzip v2-smgui image
  make package-all         Package all images

Load Targets:
  make load-v1-tiny        Load v1-tiny image from .tar.gz
  make load-v1-large       Load v1-large image from .tar.gz
  make load-v2-gui         Load v2-gui image from .tar.gz
  make load-v2-smgui       Load v2-smgui image from .tar.gz
  make load-all            Load all images

Push Target:
  make push                Push all built images to registry

Cleanup Targets:
  make clean               Remove .tar.gz export files
  make clean-images        Delete local Docker images
  make clean-all           Run both clean and clean-images

Meta:
  make status              Show current victim image versions

```

To reiterate, ***make push*** is not set up at this time.

---

All of the data used for a lab session is stored in ***INSTALL_DIR/logs/lab_session_id***

If you go looking, you will find all the answers, but that would be cheating.

Each session is self contained and you can rerun any previous lab session with ***launch_lab -i SESSION_ID***

Here is what the average Lab Session contains.  Sessions can have some differences on the number of targets launched, the services used, and so forth.

```
/opt/firing-range/logs/lab_85e2d331$ tree
.
├── bin
├── conf
│   ├── certs
│   │   ├── ca.crt
│   │   ├── ca.key
│   │   ├── console
│   │   │   ├── console.cnf
│   │   │   ├── console.crt
│   │   │   ├── console.csr
│   │   │   └── console.key
│   │   └── cyber-ninja.nfr.lab
│   │       ├── cyber-ninja.nfr.lab.cnf
│   │       ├── cyber-ninja.nfr.lab.crt
│   │       ├── cyber-ninja.nfr.lab.csr
│   │       └── cyber-ninja.nfr.lab.key
│   ├── console
│   │   ├── dnsmasq.conf
│   │   └── rsyslog.conf
│   └── nfr.lab.zone
├── docker-compose.yml
├── hostnames.map
├── lab.log
├── logs
│   ├── containers
│   ├── services
│   └── tcpdump
├── mapping.txt
├── score_card
├── services.map
└── target
    ├── conf
    │   ├── ftp
    │   ├── http
    │   │   ├── cgi-bin
    │   │   │   ├── env.cgi
    │   │   │   └── flag.cgi
    │   │   ├── css
    │   │   │   └── style.css
    │   │   ├── errors
    │   │   │   └── err.html
    │   │   ├── favicon.ico -> img/logo.svg
    │   │   ├── img
    │   │   │   └── logo.svg
    │   │   ├── index.html
    │   │   ├── js
    │   │   │   └── script.js
    │   │   ├── robots.txt
    │   │   ├── security
    │   │   │   ├── hall-of-fame.html
    │   │   │   ├── policy.html
    │   │   │   └── privacy.html
    │   │   └── security.txt
    │   ├── resolv.conf
    │   ├── rsyslog
    │   │   └── rsyslog.conf
    │   ├── smb
    │   │   └── smb.conf
    │   ├── smtp
    │   │   └── smtpd.conf
    │   ├── snmp
    │   │   ├── show_flag.sh
    │   │   └── snmpd.conf
    │   ├── ssh
    │   │   ├── banner
    │   │   └── sshd_config
    │   ├── telnet
    │   └── tftp
    │       └── README
    ├── console.nfr.lab.launch_log
    ├── cyber-ninja.nfr.lab.launch_log
    ├── dnsmasq.log
    ├── launch_target.sh
    ├── score.json
    └── services
        ├── api.sh
        ├── crap.sh
        ├── dns.sh
        ├── finger.sh
        ├── ftp.sh
        ├── http.sh
        ├── imap.sh
        ├── irc.sh
        ├── ldap.sh
        ├── memcached.sh
        ├── mysql.sh
        ├── nntp.sh
        ├── ntp.sh
        ├── pop3.sh
        ├── postgres.sh
        ├── rabbitmq.sh
        ├── rdp.sh
        ├── redis.sh
        ├── service_emulator.sh
        ├── smb.sh
        ├── smtp.sh
        ├── snmp.sh
        ├── socks4.sh
        ├── ssh.sh
        ├── telnet.sh
        ├── tftp.sh
        └── vnc.sh

26 directories, 75 files
```

