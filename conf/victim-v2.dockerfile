FROM debian:bookworm-slim

LABEL maintainer="lheath@unspecific.com"
LABEL version="1.0"
LABEL description="Victim container for nmap firing range (v2) the GUI returns"

ENV DEBIAN_FRONTEND=noninteractive

# Install XFCE desktop, XRDP, VNC, and support tools
RUN apt-get update && apt-get install -y \
    xfce4 \
    xrdp \
    x11vnc \
    dbus-x11 \
    sudo \
    net-tools \
    iproute2 \
    iputils-ping \
    curl \
    bash \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Create runtime target directory where scripts will be mounted
RUN mkdir -p /opt/target

# Create default user (can be used by emulator scripts)
RUN useradd -m -s /bin/bash labuser && \
    echo "labuser:labuser" | chpasswd && \
    adduser labuser sudo

# Set XFCE as default session
RUN echo xfce4-session > /etc/skel/.xsession && \
    cp /etc/skel/.xsession /home/labuser/.xsession && \
    chown labuser:labuser /home/labuser/.xsession

# Configure xrdp to use XFCE
RUN sed -i.bak 's/^test -x/# test -x/' /etc/xrdp/startwm.sh && \
    echo "startxfce4" >> /etc/xrdp/startwm.sh

# Working directory
WORKDIR /opt/target

# The actual emulator or control logic will be mounted in via volume
CMD ["/bin/bash", "/opt/target/launch_target.sh"]
