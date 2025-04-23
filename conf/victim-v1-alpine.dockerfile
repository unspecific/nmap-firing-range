FROM alpine:3.18

LABEL maintainer="lheath@unspecific.com"
LABEL version="1.0"
LABEL description="Victim container for nmap firing range (tiny)"

ENV DEBIAN_FRONTEND=noninteractive

# Install services & tools
RUN apk add --no-cache \
    bash \
    openssh-server \
    samba samba-common-tools \
    dnsmasq \
    busybox-syslogd \
    nmap-ncat

# Create directory for session-mounted volume
RUN mkdir -p /opt/target

# Ensure SSH host keys directory exists
RUN mkdir -p /etc/ssh

# Create default syslog directory
RUN mkdir -p /var/log

# Set working directory
WORKDIR /opt/target

# Entrypoint always runs volume-mounted session code
CMD ["/opt/target/launch_target.sh"]
