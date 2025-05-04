#!/usr/bin/env bash
set -euo pipefail

# ─── Privilege check ─────────────────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
  echo " 🔒 Root access required. Re-running with sudo..."
  exec sudo "$0" "$@"
fi

APP="NFR Cleanup"
VERSION="2.2.9"
LOG_DIR="logs"
BIN_DIR="bin"

# ─── Auto-discover your project root ────────────────────────────────────────
# Script lives in project_root/bin/cleanup_lab.sh
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
LAB_DIR="$PROJECT_ROOT"    # so logs/ is under PROJECT_ROOT/logs

# ─── Determine the score_card file (default ./score_card) ───────────────────
if [[ $# -gt 1 ]]; then
  echo "Usage: $0 [score_card_file]" >&2
  exit 1
elif [[ $# -eq 1 ]]; then
  SUBMISSION_FILE="$1"
else
  SUBMISSION_FILE="./score_card"
fi

if [[ ! -f "$SUBMISSION_FILE" ]]; then
  echo " ❌ Score card not found: $SUBMISSION_FILE" >&2
  echo "Run this from the project root (where score_card was generated)." >&2
  exit 1
fi

# ─── Extract session ID from the score_card ─────────────────────────────────
SESSION_ID=$(grep -m1 '^session=' "$SUBMISSION_FILE" | cut -d'=' -f2-)
if [[ -z "$SESSION_ID" ]]; then
  echo " ❌ session= not found in $SUBMISSION_FILE" >&2
  exit 1
fi

SESSION_DIR="$LAB_DIR/$LOG_DIR/lab_$SESSION_ID"
SERVICES_MAP="$SESSION_DIR/services.map"
COMPOSE_FILE="$SESSION_DIR/docker-compose.yml"

echo
echo " 🎩  $APP v$VERSION - Lee 'MadHat' Heath <lheath@unspecific.com>"
echo " 🔁  Cleaning up session $SESSION_ID in $SESSION_DIR"

# ─── Sanity checks ────────────────────────────────────────────────────────────
if [[ ! -f "$SERVICES_MAP" ]]; then
  echo " ❌ Lab session not found at $SESSION_DIR" >&2
  exit 1
fi
if [[ ! -f "$COMPOSE_FILE" ]]; then
  echo " ❌ Compose file not found at $COMPOSE_FILE" >&2
  exit 1
fi

# ─── Tear down via docker-compose (ignore errors) ────────────────────────────
echo " 🛑  Bringing down containers, networks, and volumes via Compose..."
docker compose -f "$COMPOSE_FILE" down -v --remove-orphans || true

# ─── Fallback: manual cleanup of containers & volumes ────────────────────────
while read -r cname; do
  [[ -z "$cname" || "$cname" =~ ^# ]] && continue

  if docker ps -a --format '{{.Names}}' | grep -xq "$cname"; then
    echo " 🗑️  Removing container: $cname"
    docker rm -f "$cname" >/dev/null || true
  fi

  if docker volume ls -q | grep -xq "$cname"; then
    echo " 🗑️  Removing volume:    $cname"
    docker volume rm "$cname" >/dev/null || true
  fi
done < <(grep -vE '^\s*#|^\s*$' "$SERVICES_MAP")

# ─── Remove the lab network ─────────────────────────────────────────────────
NETWORK="range-$SESSION_ID"
echo " 🌐  Removing network: $NETWORK"
docker network rm "$NETWORK" &>/dev/null || echo " ⚠️  Network already gone"

# ─── Backup score_card into session dir ────────────────────────────────────
if [[ -L "$SUBMISSION_FILE" ]]; then
  echo " 📄  Detected score_card symlink; removing it"
  rm -f "$SUBMISSION_FILE"
elif [[ -f "$SUBMISSION_FILE" ]]; then
  echo " 📄  Backing up score_card into session directory"
  cp "$SUBMISSION_FILE" "$SESSION_DIR/score_card" || echo " ⚠️  Failed to backup score_card"
else
  echo " ℹ️  No score_card found; skipping backup"
fi

# ─── Clean up /etc/hosts entries for this session ───────────────────────────
echo " 🧹  Cleaning up /etc/hosts"
grep -v "# $SESSION_ID" /etc/hosts > /etc/hosts.tmp
mv /etc/hosts.tmp /etc/hosts

echo
echo " ✅  Lab environment cleanup complete."
echo " ⏱️  Completed in $SECONDS seconds"
