# Base image
FROM debian:bookworm-slim

# 
LABEL maintainer="lheath@unspecific.com"
LABEL version="1.0"
LABEL description="Victim container for nmap firing range (v1)"


ENV DEBIAN_FRONTEND=noninteractive

# Install tools and services
RUN apt-get update && apt-get install -y \
    openssh-server \
    samba \
    tftpd-hpa \
    ncat \
    bash \
    curl \
    iproute2 \
    iputils-ping \
    && apt-get clean && rm -rf /var/lib/apt/lists/*  /tmp/* /var/tmp/*

# Create runtime directory where volume will mount
RUN mkdir -p /opt/target

# Set working directory to /opt/target
WORKDIR /opt/target

# Entrypoint runs the session-injected launch_target.sh
CMD ["/bin/bash", "/opt/target/launch_target.sh"]
