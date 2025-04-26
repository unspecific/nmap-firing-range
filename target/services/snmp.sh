#!/bin/bash

# ─── Emulator Metadata ─────────────────────────────────────────────────────
EM_PORT="tcp:161 udp:161"               # The port this service listens on
EM_VERSION="3.6.1"               # Optional version identifier
EM_DAEMON="FakeSNMP"
EM_DESC="Simple SNMP, guess the community"  # Short description for listing output


# Simulated SNMP response server (read-only fake)
# Not a real BER/ASN.1 parser — this just looks like SNMP output to users or scripts

echo "Received SNMP query"

while read -r line; do
    # Simulate community string detection
    if echo "$line" | grep -qi "$COMMUNITY"; then
        echo "SNMPv2-MIB::sysDescr.0 = STRING: Fake SNMP Device running $EM_DAEMON/$EM_VERSION"
        echo "SNMPv2-MIB::sysContact.0 = STRING: root@$HOSTNAME"
        echo "SNMPv2-MIB::sysLocation.0 = STRING: Somewhere in /dev/null"
        echo "SNMPv2-MIB::flag.0 = STRING: $FLAG"
    else
        echo "SNMP Error: Invalid community string"
    fi
done
