#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# ─── Emulator Metadata ─────────────────────────────────────────────────────
EM_PORT="tcp:53 udp:53"             
EM_VERSION="9.11"                   
EM_DAEMON="FakeDNS"                 
EM_DESC="Simple DNS emulator with TXT-flag record"  

HOST=$(hostname)
DOMAIN="${DOMAIN:-nfr.lab}"              # default domain
FLAG="${FLAG:-flag{dns-emulator-flag}}"  # injected CTF flag
FLAG_SUBDOMAIN="flag.${DOMAIN}"

# Banner on start
echo "$EM_DAEMON/$EM_VERSION on $HOST ready for DNS queries in $DOMAIN"

# Read queries as "<name> <type>"
while IFS= read -r line; do
    # log for scoring
    echo "[*] DNS query: $line"

    # split name & type
    read -r qname qtype <<<"$line"
    qtype=${qtype^^}

    case "$qtype" in
      A)
        # flag subdomain just returns a harmless IP
        if [[ "$qname" == "$FLAG_SUBDOMAIN" ]]; then
          echo "A 10.0.0.99"
        else
          echo "A 192.0.2.1"
        fi
        ;;
      AAAA)
        echo "AAAA ::1"
        ;;
      NS)
        echo "NS ns1.${DOMAIN}"
        echo "NS ns2.${DOMAIN}"
        ;;
      MX)
        echo "MX 10 mail.${DOMAIN}"
        ;;
      TXT)
        if [[ "$qname" == "$FLAG_SUBDOMAIN" ]]; then
          # This is where the flag lives
          echo "TXT \"$FLAG\""
        else
          echo "TXT \"v=spf1 include:${DOMAIN} ~all\""
        fi
        ;;
      ANY)
        # return a mix of records
        echo "A 192.0.2.1"
        echo "NS ns1.${DOMAIN}"
        echo "MX 10 mail.${DOMAIN}"
        echo "TXT \"<default text record>\""
        ;;
      *)
        echo "ERROR unsupported query type: $qtype"
        ;;
    esac
done

# Give scanners a moment to grab the last reply
sleep 1
