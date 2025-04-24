#!/bin/bash
# ─── Emulator Metadata ─────────────────────────────────────────────────────
EM_PORT="9999"               # The port this service listens on
EM_VERSION="1.1"               # Optional version identifier
EM_DAEMON="Unspecific IRCd"
EM_DESC="Custom interface"  # Short description for listing output


echo -e "FakeLDAP v0.1 Ready\r"

while IFS= read -r line; do
    cmd=$(echo "$line" | awk '{print tolower($1)}')
    args=$(echo "$line" | cut -d' ' -f2-)

    case "$cmd" in
        bind)
            echo -e "bind OK - anonymous bind accepted\r"
            ;;
        version)
            echo -e "version: 3\r"
            ;;
        search)
            if [[ "$args" == *"cn=flag"* ]]; then
                echo -e "dn: cn=flag,dc=fake,dc=local\r"
                echo -e "cn: flag\r"
                echo -e "description: flag{ldap-enumeration-win}\r"
                echo -e ".\r"
            else
                echo -e "No results found for search: $args\r"
            fi
            ;;
        whoami)
            echo -e "dn: anonymous\r"
            ;;
        quit|exit)
            echo -e "Goodbye.\r"
            break
            ;;
        *)
            echo -e "Unrecognized command: $cmd\r"
            ;;
    esac
done
