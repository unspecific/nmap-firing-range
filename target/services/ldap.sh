#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# ─── Emulator Metadata ─────────────────────────────────────────────────────
EM_PORT="tcp:389 tcp:636:tls"
EM_VERSION="14.667"
EM_DAEMON="FakeLDAP"
EM_DESC="LDAP w/ Anonymous & Simple Bind, filterable search"

# ANSI colors
BOLD=$'\e[1m'; CYAN=$'\e[36m'; RESET=$'\e[0m'

# Session state
BOUND_DN="anonymous"
AUTHENTICATED=false

# Sample directory entries
declare -A ENTRIES

ENTRIES["dc=fake,dc=local"]=$'objectClass: top\nobjectClass: dcObject\ndc: fake'
ENTRIES["ou=users,dc=fake,dc=local"]=$'objectClass: top\nobjectClass: organizationalUnit\nou: users'
ENTRIES["cn=alice,ou=users,dc=fake,dc=local"]=$'objectClass: inetOrgPerson\ncn: alice\nsn: Wonderland\nmail: alice@fake.local'
ENTRIES["cn=bob,ou=users,dc=fake,dc=local"]=$'objectClass: inetOrgPerson\ncn: bob\nsn: Builder\nmail: bob@fake.local'
ENTRIES["cn=charlie,ou=users,dc=fake,dc=local"]=$'objectClass: inetOrgPerson\ncn: charlie\nsn: Chaplin\nmail: charlie@fake.local'
ENTRIES["cn=flaguser,ou=users,dc=fake,dc=local"]=$'objectClass: inetOrgPerson\ncn: flaguser\nsn: Challenger\ndescription: '"$FLAG$"

# Optional simple admin credential
ADMIN_DN="cn=admin,dc=fake,dc=local"
ADMIN_PASS="${PASSWORD:-adminpass}"

banner() {
  printf "%b" "${CYAN}${BOLD}"
  cat <<'EOF'
   _     _    ____  ___  ____  
  | |   / \  |  _ \|_ _|/ ___| 
  | |  / _ \ | |_) || | \___ \ 
  | | / ___ \|  _ < | |  ___) |
  |_|/_/   \_\_| \_\___||____/ 
EOF
  printf "%b\n" "${RESET}"
  echo "$EM_DAEMON/$EM_VERSION Ready"
}

# Perform an LDIF dump of a single entry
print_entry() {
  local dn="$1"
  echo "dn: $dn"
  IFS=$'\n' read -r -d '' -a attrs <<<"${ENTRIES[$dn]}"$'\0'
  for attr in "${attrs[@]}"; do
    echo "$attr"
  done
  echo
}

# Search for entries matching base & simple (cn=xyz) filter
handle_search() {
  local base="$1" scope="$2" filter="$3"
  # strip parentheses, e.g. "(cn=alice)" -> "cn=alice"
  filter="${filter#(}"; filter="${filter%)}"
  IFS='=' read -r attr val <<<"$filter"

  for dn in "${!ENTRIES[@]}"; do
    # check DN under base
    if [[ "${dn,,}" == *"${base,,}"* ]]; then
      # check attribute match in LDIF blob
      if grep -qi "^${attr}:\s*${val}$" <<<"${ENTRIES[$dn]}"; then
        print_entry "$dn"
      fi
    fi
  done
  echo "."  # end of results
}

# Main loop
banner
while IFS= read -r line || [[ -n "$line" ]]; do
  # parse command and args
  cmd=$(echo "$line" | awk '{print tolower($1)}')
  args="${line#* }"

  case "$cmd" in
    bind)
      # support anonymous or simple bind: bind <dn> <pass>
      IFS=' ' read -r _ dn pass <<<"$line"
      if [[ -z "$dn" || "$dn" == "anonymous" ]]; then
        BOUND_DN="anonymous"
        AUTHENTICATED=true
        echo "bind OK - anonymous bind accepted"
      elif [[ "$dn" == "$ADMIN_DN" && "$pass" == "$ADMIN_PASS" ]]; then
        BOUND_DN="$ADMIN_DN"
        AUTHENTICATED=true
        echo "bind OK - simple bind as admin"
      else
        AUTHENTICATED=false
        echo "bind ERROR - invalid credentials"
      fi
      ;;
    version)
      echo "version: $EM_DAEMON/$EM_VERSION"
      ;;
    whoami)
      echo "dn: $BOUND_DN"
      ;;
    search)
      # usage: search <baseDN> <scope> <filter>
      IFS=' ' read -r _ base scope filter <<<"$line"
      if ! $AUTHENTICATED; then
        echo "ERROR - not bound"
      else
        handle_search "$base" "$scope" "$filter"
      fi
      ;;
    rootdse)
      # advertise supported controls / namingContexts
      echo "namingContexts: dc=fake,dc=local"
      echo "supportedControl: 1.2.840.113556.1.4.319"
      echo "supportedExtension: 1.3.6.1.4.1.1466.20037"
      echo "."
      ;;
    quit|exit)
      echo "Goodbye."
      break
      ;;
    *)
      echo "Unrecognized command: $cmd"
      ;;
  esac
done

sleep 1  # let scanners grab final output
