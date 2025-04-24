#!/bin/bash

# ─── Emulator Metadata ─────────────────────────────────────────────────────
EM_PORT="9999"               # The port this service listens on
EM_VERSION="1.1"               # Optional version identifier
EM_DAEMON="Unspecific SNMPd"
EM_DESC="Custom interface"  # Short description for listing output


# Simulated SNMP response server (read-only fake)
# Not a real BER/ASN.1 parser — this just looks like SNMP output to users or scripts

echo "Received SNMP query"

while read -r line; do
    # Simulate community string detection
    if echo "$line" | grep -qi "public"; then
        echo "SNMPv2-MIB::sysDescr.0 = STRING: Fake SNMP Device running FakeOS 1.0"
        echo "SNMPv2-MIB::sysContact.0 = STRING: root@fake.local"
        echo "SNMPv2-MIB::sysLocation.0 = STRING: Somewhere in /dev/null"
        echo "SNMPv2-MIB::flag.0 = STRING: flag{snmp-public-read-win}"
    else
        echo "SNMP Error: Invalid community string"
    fi
done
