FROM alpine:3.18

LABEL maintainer="lheath@unspecific.com"
LABEL version="1.0"
LABEL description="Victim container for nmap firing range (tiny)"

ENV DEBIAN_FRONTEND=noninteractive

# Install services & tools
RUN apk update && apk add --no-cache alpine-conf \
    bash openssh-server net-snmp openldap \
    samba samba-common-tools dovecot dovecot-pop3d \
    dnsmasq rsyslog nmap-ncat vsftpd tftp-hpa opensmtpd

RUN setup-hostname -n victim-v2.nfr.lab

# Create lab directories for session-mounted volumes
RUN mkdir -p /opt/target /etc/ssh /var/log

# the GUI needs a user to be set up
RUN setup-user -a -f "Admin J Victim" -g "admin,wheel" admin

# set a default admin password
RUN sed -i 's|^admin:[^:]*:|admin:$6$1mgLiGpX7PbpJHIT$r6fEVHndETFcZCr1QPKCKfpDJQPg3ZZMCA8zGTilpaQRnsQdQItW9EPzm8kPwqSloyyk2y1/F9EgOucHVok48/:|' /etc/shadow

# Now we will set up the GUI
RUN setup-wayland-base ${BROWSER:-firefox} \
	font-dejavu foot grim i3status sway \
	swayidle swaylockd util-linux-login \
	wl-clipboard wmenu xwayland "$@"

# Set working directory
WORKDIR /opt/target

# Entrypoint always runs volume-mounted session code
CMD ["/opt/target/launch_target.sh"]
