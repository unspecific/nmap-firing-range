
# Nmap Firing Range

## 🔥 Nmap Firing Range Project

The **Nmap Firing Range** project began organically when one of our employees requested a way to practice using Nmap while studying for an upcoming certification exam. To accelerate development, we leveraged ChatGPT to assist in quickly gathering details about a wide range of network services, protocols, and application behaviors — helping us decrease the research and setup time significantly.

What started as a simple idea has evolved into a flexible, containerized lab environment designed for real-world Nmap practice, reconnaissance training, and service enumeration exercises.

### Key Features

- **Containerized Environment:**  
  Each service is launched in an isolated Docker container, allowing easy resets, scalability, and modularity. Users can spin up individual targets or a full lab environment on demand.

- **Randomized Targets:**  
  Each lab session creates a /24 network in 192.168.0.0/16, and each host has a random IP, ensuring that scans mimic real-world unpredictability. This helps participants move beyond relying on standard ports and easily recognizable service signatures.

- **Service Emulation:**  
  A wide range of classic network services are emulated, including:
  - Finger
  - FTP
  - HTTP
  - LDAP
  - SMTP
  - Telnet
  - DNS
  - Custom or vulnerable services

  These emulated services will fingerprint as the service for nmap, can support brute forcing, and other protocol specific tricks. 

- **TLS/SSL Support:**  
  Many services can optionally be configured to support SSL/TLS, requiring scanners to properly detect and negotiate secure sessions.  Each session,LS support is disabled, generates a new CA for the lab session.  Each host has a unique hostname, and a server certificate signed by the CA.

- **Dynamic Credential Generation:**  
  Each service can receive randomly generated usernames and passwords at launch, preventing users from relying on default credentials and promoting proper enumeration techniques.  This includes snmp communities and other authenitcation methds to allow for brute forcing.

- **Custom Service Banners: TBD**  
  Banners are randomized at container start to simulate different application versions, operating systems, and server responses, making fingerprinting and enumeration exercises more challenging and authentic.

- **Logging for Scoring and Review:  PARTIAL**  
  Services include logging capabilities to capture user interaction. This enables scoring, post-scan analysis, and training feedback without affecting the live lab environment.

- **DNS and Reverse DNS (PTR)**  
  A full DNS environment is simulated using Dnsmasq, including forward and reverse (PTR) records. This allows students to practice identifying services based on DNS enumeration rather than only IP scanning.

- **Syslog Server Integration:**  
  All container logs are sent to a centralized syslog server, which also acts as the environment’s DNS server. Logs persist across container restarts for full session visibility.

- **Dashboard, Log analysis Support:  TBD**  
  The environment is extensible to incorporate log visualization and searching during live sessions, enabling students to correlate scans, review activity, and understand service interactions at a deeper level.


### Project Goals

- Provide a practical, repeatable environment for Nmap training and service discovery.
- Build muscle memory around real-world scanning, port mapping, banner grabbing, and basic vulnerability identification.
- Teach participants to adjust scanning techniques dynamically when encountering randomized environments.
- Allow easy extension to new services, protocols, and security scenarios for advanced training.

- Make it a game.  Lab challanges can be created and shared.
- The program is extensible.  The emulated service can be dropped into a folder to add more service options.


I have included a [list of available servises](./nfr-target-services.txt) to show what services are supported.  As of now not ll work 100% of the time.  That is the next task.

I have also included a [sample scan](./sample_scan.txt)

---

# Installation

If you hve internet access on the host you want to instll the firing range on,
- download the [setup_lab.sh](https://raw.githubusercontent.com/unspecific/nmap-firing-range/refs/heads/main/bin/setup_lab.sh) file.
- chmod 755 setup_lab.sh
- ./setup_lab.sh

This will allow you to install directly from GitHib.

You can also download the package to install on an ofline host.  
- download the [NFR Zip](https://github.com/unspecific/nmap-firing-range/archive/refs/heads/main.zip)
- unzip the file.  It wll create a folder called nmap-firing-range
- cd nmap-firing-range/bin
- chmod 755 setup_lab.sh
- ./setup_lab.sh

During the install it will see the local files and give an option to download or use the local files. 

Once instaled, you can use setup_lab to unsinatll or update the system

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

- launch_lab - For setup and launcing a new lab session
- check_lab - For scoring your findings.  Moving to a web interface on the console server
- cleanup_lab - Removed all te containers, networks, configuration entries used for the lab session

---

lanch_lab is the real workhose of the project and most of wat is listed above is covered here.
It does add a group and adds the curent user for easier acces to the lab files.

launch_lab does relaunch with sudo when setting up a lab, but not a few options, like help and list services.

During the first run it will check tomake sure you have docker and the required image installed.  It is ***unspecific/victim-v1-tiny***

It included with theinsta package and is 22M compressed and ~78M in action.  If you want to build your own container locally, it is based on Alpine Linux, and in the <conf/> directory is a make file to buildit yourself.  We will cover that below.


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
  -l             List available services and exit
  -V             Show version and exit
  -h             Show this help message and exit
```

---

check_lab has minimal optnions.  By defualt it looks for the score_card in the PWD, and uses that to score against.  You can also specify the specific score_card you want to use.

I have started creating a web interface for scoring. Once launched you can point a pbrowser to http://console.nfr.lab/ assuming you are running it locally, as it add an entray to /etc/hosts to allow access by name.  This entry is removed when the cleanup_lab is run.

```
$ check_lab -h
Usage: check_lab [OPTIONS] [SCORE_CARD_FILE]

Options:
  --name NAME         Set the name displayed in the header (will be added to score_card)
  --help, -h          Show this help message and exit
```

---

The last script in the project is ***cleanup_lab***
It removes all evidense of thelab session except for the lab directory (***/opt/firing-rang/*** is the defalt)

```
cleanup_lab
```

* need to make a help output.

It is similar to check_lab where it looks for ***./score_card*** to used the session ID in the score_card for cleanup, or you can call it with a specific score_card.

---

As menioned in the <conf/> directory (Default instal locaiton is ***/opt/firing-range/conf/***) there is a Makefile.  This is used ot build and manae the Docker imaes used.  The only one used today is ***victim-v1-tiny***

As of this time te iages are not added to docker hub.

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

to reitterate, ***make push*** is not set up at this time.

---

All of the data used for a lab session is stored in ***INSTAL_DIR/logs/lab_sesion_id***

If you go looking, you will find all the answers, but that would be cheating.

Each session is self contained and you can rerun any previous lab session with ***launch_lab -i SESSION_ID***

Here is what the average Lab Session contains.  Sesions can have some differences on the number of targets launched, te services used, and so forth.

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

