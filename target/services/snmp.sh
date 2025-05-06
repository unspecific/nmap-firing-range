#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# ─── Emulator Metadata ─────────────────────────────────────────────────────
EM_PORT="tcp:161 udp:161"
EM_VERSION="3.6.1"
EM_DAEMON="FakeSNMP"
EM_DESC="SNMPv2c emulator with GET/GETNEXT/WALK"

HOSTNAME=$(hostname)
COMM_EXPECT="${COMMUNITY:-public}"
FLAG_OID="SNMPv2-MIB::flag.0"

# Predefined OID → value map
declare -A OIDS=(
  ["SNMPv2-MIB::sysDescr.0"]="STRING: Fake SNMP Device running $EM_DAEMON/$EM_VERSION"
  ["SNMPv2-MIB::sysObjectID.0"]="OBJECTID: .1.3.6.1.4.1.8072.3.2.10"
  ["SNMPv2-MIB::sysUpTime.0"]="Timeticks: (12345678) 1:23:45.67"
  ["SNMPv2-MIB::sysContact.0"]="STRING: root@$HOSTNAME"
  ["SNMPv2-MIB::sysName.0"]="STRING: $EM_DAEMON-$HOSTNAME"
  ["SNMPv2-MIB::sysLocation.0"]="STRING: Somewhere in /dev/null"
  ["$FLAG_OID"]="STRING: $FLAG"
)

# Sorted list of OIDs for GETNEXT/WALK
oids_sorted=( $(printf '%s\n' "${!OIDS[@]}" | sort) )

# Helpers
print_oid() { printf "%s = %s\n" "$1" "${OIDS[$1]}"; }

handle_get() {
  local oid=$1
  if [[ -n "${OIDS[$oid]+_}" ]]; then
    print_oid "$oid"
  else
    echo "SNMP Error: noSuchName"
  fi
}

handle_getnext() {
  local oid=$1 idx next
  for i in "${!oids_sorted[@]}"; do
    [[ "${oids_sorted[i]}" == "$oid" ]] && idx=$i && break
  done
  next=$(( idx + 1 ))
  if (( next < ${#oids_sorted[@]} )); then
    print_oid "${oids_sorted[next]}"
  else
    echo "SNMP Error: endOfMibView"
  fi
}

handle_walk() {
  local prefix=$1
  for oid in "${oids_sorted[@]}"; do
    if [[ $oid == $prefix* ]]; then
      print_oid "$oid"
    fi
  done
}

# -- start --
echo "SNMP emulator $EM_DAEMON/$EM_VERSION starting (expect community: '$COMM_EXPECT')"

# First line MUST be the community string
read -r line || exit
if [[ "${line##* }" != "$COMM_EXPECT" ]]; then
  echo "SNMP Error: Invalid community string"
  exit 1
fi

# Now process commands
while read -r line; do
  # each line: COMMAND OID
  cmd=${line%% *}
  arg=${line#* }
  case "${cmd^^}" in
    GET)
      handle_get "$arg"
      ;;
    GETNEXT)
      handle_getnext "$arg"
      ;;
    WALK)
      handle_walk "$arg"
      ;;
    QUIT|EXIT)
      echo "SNMP emulator: closing"
      break
      ;;
    *)
      echo "SNMP Error: unsupported command '$cmd'"
      ;;
  esac
done

sleep 1  # give scanners time to grab final output
