
# Nmap Firing Range
I started with AI, but as the code got more complex the AI started making a lot of mistakes.
The initial setup was AI, and then I tweaked it and expanded on it.

## 🔥 Nmap Firing Range Toolkit

**The Nmap Firing Range** is a self-contained, replayable lab environment built for practicing real-world network enumeration and service exploitation techniques using `nmap` and similar tools.

Designed as a **live-fire training ground**, this toolkit launches randomized sets of Docker-based targets simulating real services—each one hiding flags across various protocols and configurations.

---

### 🎯 Key Features:

- **Dynamic Lab Generation**: Every session spins up targets on randomized IPs and ports, ensuring unique scans every time.
- **Real Services, Real Flags**: Targets include protocols like FTP, SMB, SSH, Telnet, HTTP, and more—each configured with hidden `FLAG{}` strings retrievable via fingerprinting, brute-force, or banner-grabbing techniques.
- **Scoring Built In**: Your findings are automatically checked against the session’s flag map. Scorecards show what you got right, what was missed, and where to improve.
- **Session Replay**: Labs are fully archived, including mapping, target configurations, and user-submitted scorecards. Easily revisit past challenges or measure progress over time.
- **Ideal for Nmap Drills**: Hone skills using advanced nmap switches (`-sV`, `--script`, `-p-`, `--version-intensity`, etc.) to fingerprint services and extract clues.

# Supported targets
The system has been set up with a nuber of target services.
- http
- ssh
- ftp
- smb
- telnet
- other
- tftp
- snmp
- smtp
- imap
- pop
- vnc


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

