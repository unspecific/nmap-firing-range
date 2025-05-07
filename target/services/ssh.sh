#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# ─── Emulator Metadata ─────────────────────────────────────────────────────
EM_PORT="tcp:22"      # SSH ports
EM_VERSION="2.666"                   # Fake SSH version
EM_DAEMON="SSH"
EM_DESC="SSH banner + pseudo shell login"

ssh_daemons=(
  AsyncSSH
  OpenSSH
  moxa
  SSH
  TECHNICOLOR_SW
  CompleteFTP
  MS
  NA
  EchoSystem_Server
  SERVER
)

randaemon=$(printf "%s\n" "${ssh_daemons[@]}" | shuf -n1)

# Send SSH version banner
# Clients (or nmap) will see this as an SSH service fingerprint
printf "SSH-2.0-%s_%s\r\n" "$randaemon" "$EM_VERSION"

# Optional pause for scanners
sleep 1

# Pseudo-login prompt over plain text
# Users can connect via 'nc' and type credentials

# Prompt for username
printf "login as: "
read -r attempt_user

# Prompt for password (silent input)
printf "password: "
read -rs attempt_pass
printf "\n"

# Check against environment USERNAME and PASSWORD
if [[ "${attempt_user}" == "${USERNAME:-}" && "${attempt_pass}" == "${PASSWORD:-}" ]]; then
  printf "Welcome to %s@%s\n" "$USERNAME" "${HOSTNAME:-localhost}"
  printf "%s\n" "$FLAG"
else
  printf "Permission denied, please try again.\n"
fi

# Keep connection open briefly
sleep 1
