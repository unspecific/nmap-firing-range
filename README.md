
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


# launch_lab

Launch lab output

```
$ sudo launch_lab 

 🎩  Nmap Firing Range (NFR) Launcher v0.5 - Lee 'MadHat' Heath <lheath@unspecific.com>
 🚀  Launching random lab at 2025-04-13_11-27-10
 🆔  SESSION_ID 4bde1556f990245799903eaaa8bc6c48
 ℹ️   Docker network 'pentest-net' not found. It will be created by the script.
 ✅  All required components are present.
 🌐  Creating Subnet for Scanning - 192.168.200.0/24
fd3140f83bf9d5a961b2c86ccd245d85fd0271962da3097d0120729590a90b1d
 ➕  Enabling Serice port #1
 ➕  Enabling Serice port #2
 ➕  Enabling Serice port #3
 ➕  Enabling Serice port #4
 ➕  Enabling Serice port #5
 ➕  Enabling Serice port #6
 ➕  Enabling Serice port #7
 ➕  Enabling Serice port #8
 🚀  Launching 5 targets with 8 open ports. Good Luck
[+] Running 5/5
 ✔ Container telnet_host   Started 0.3s 
 ✔ Container http_host     Started 0.3s 
 ✔ Container smb_host      Started 0.2s 
 ✔ Container ssh_host      Started 0.3s 
 ✔ Container netcat_host   Started 0.3s 
Your Firing Range has been launched.
```

# cleanup_lab

Cleanup script output

```
$ sudo cleanup_lab 

 🎩  NFR Cleanup v0.4 - Lee 'MadHat' Heath <lheath@unspecific.com>
 🛑  Stopping and removing containers...
[+] Running 5/5
 ✔ Container ssh_host      Removed 0.2s 
 ✔ Container smb_host      Removed 0.3s 
 ✔ Container netcat_host   Removed 10.2s 
 ✔ Container telnet_host   Removed 0.0s 
 ✔ Container http_host     Removed 0.3s 
 🌐 Removing lab network (pentest-net)...
pentest-net
 🗑️  Removing unused Docker volumes...
Deleted Volumes:
66f21d34205256a7bcf5604fad5ca4cf0bcc9c1cc8f25286d30bced50ff38d3a
8855ed83dc61b0617d5894c3522aec8e293d81d3f28bc5d04c37018bcf3ba69a
fc86bba86027d80f07ff018780d29b48df06e2432925e992ddb1784a22e22838
6946e3915440430b97c2ed2e3f7540734147e1ca8b9d76ea82d5a31c265075c4
ad605dc4e89c7bbf6238734305ca50a9e0d26be5043a27c9a23eab383da7eb92

Total reclaimed space: 4.595MB
 🧹 Cleaning up generated lab files and directories...
 ✅ Lab environment cleanup complete.
```




#  Scorecard format

```
session=9f01175ee5e7645df7d3d0c2e7747dd7
service=telnet target=192.168.200.153 port=5537 proto=tcp flag=FLAG{89ea16740192885a}
service=http target=192.168.200.46 port=80 proto=tcp flag=FLAG{7bb9aae3d2bc34d0}
service=telnet target=192.168.200.24 port=23 proto=tcp flag=FLAG{7ca3d11760335622}
service=ssh target=192.168.200.20 port=22 proto=tcp flag=FLAG{d6a91cde647db}
```

# check_lab script

```
$ check_lab.sh score_card 

 🎩  NFR-CheckLab v0.5 - Lee 'MadHat' Heath <lheath@unspecific.com>
✅ SESSION_ID: 9f01175ee5e7645df7d3d0c2e7747dd7 - Scoring session started
---------------------------
❌ telnet 192.168.200.153:5537:tcp → No Flag Match -1 pts
✅ telnet 192.168.200.153:5537:tcp → Network correct (misidentified service) +4 pts
✅ http 192.168.200.46:80:tcp → Flag Match +5 pts
✅ http 192.168.200.46:80:tcp → Network Identified (IP, Port and Protocol are correct) +3 pts
✅ telnet 192.168.200.24:23:tcp → Flag Match +5 pts
✅ telnet 192.168.200.24:23:tcp → Network Identified (IP, Port and Protocol are correct) +3 pts
❌ ssh 192.168.200.20:22:tcp → No Flag Match -1 pts
✅ ssh 192.168.200.20:22:tcp → Network Identified (IP, Port and Protocol are correct) +3 pts
---------------------------
🧮 Score: 21
✔️  Correct: 15
❌ Incorrect: 9
🕵️  Missed services:
- ❗ 192.168.200.139:21:tcp was not reported
```

