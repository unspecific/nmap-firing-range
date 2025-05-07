
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

