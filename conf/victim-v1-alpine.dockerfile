FROM alpine:3.18

LABEL maintainer="lheath@unspecific.com"
LABEL version="1.3"
LABEL description="Victim container for nmap firing range (tiny)"

ENV DEBIAN_FRONTEND=noninteractive

# Install services & tools
RUN apk update && apk add --no-cache alpine-conf thttpd bash openssh-server net-snmp openldap samba samba-common-tools imap dnsmasq rsyslog nmap-ncat vsftpd tftp-hpa opensmtpd

# Create directory for session-mounted volume
RUN mkdir -p /opt/target /etc/ssh /var/log


# Set working directory
WORKDIR /opt/target

# Entrypoint always runs volume-mounted session code
CMD ["/opt/target/launch_target.sh"]
