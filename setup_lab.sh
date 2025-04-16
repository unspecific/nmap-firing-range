#!/bin/bash

# setup_lab.sh - Installer for the Firing Range Pentest Lab

set -euo pipefail

# Ensure the script is run as root or with sudo
if [[ "$EUID" -ne 0 ]]; then
  echo "🔒 Root access required. Re-running with sudo..."
  exec sudo "$0" "$@"
fi

### CONFIG ###
INSTALL_DIR="/opt/firing-range"
BIN_DIR="$INSTALL_DIR/bin"
LOG_DIR="$INSTALL_DIR/logs"
LOGFILE="$LOG_DIR/setup.log"
SCRIPTS=("launch_lab.sh" "cleanup_lab.sh" "check_lab.sh" "setup_lab.sh")
ROLLBACK_FILE="$LOG_DIR/installed_files.txt"

### FUNCTIONS ###
log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOGFILE"
}

show_help() {
  echo "Firing Range Setup Script"
  echo "Usage: $0 [OPTIONS]"
  echo
  echo "Options:"
  echo "  --help, -h         Show this help message and exit"
  echo "  --uninstall        Uninstall all installed components and optionally backup logs"
  echo "  --no-prompt        Skip GitHub update prompt and use local scripts"
  echo "  --skip-update      Internal flag to avoid update loop after pulling latest scripts"
  echo "  --force            Overwrite all existing scripts without prompting"
  echo
  echo "This script installs or updates the Firing Range lab to /opt/firing-range,"
  echo "ensures all dependencies are met, installs shell scripts, creates symlinks,"
  echo "and can pull the latest scripts from GitHub."
  echo
  exit 0
}

check_dependencies() {
  log "Checking required dependencies..."
  local deps=(docker git curl)
  for dep in "${deps[@]}"; do
    if ! command -v "$dep" &>/dev/null; then
      echo "❌ Missing dependency: $dep"
      exit 1
    fi
  done

  # no GitHub auth required

  log "All dependencies satisfied."
}

create_directories() {
  log "Creating directory structure..."
  mkdir -p "$BIN_DIR" "$LOG_DIR"
}

install_scripts() {
  log "Installing scripts to $BIN_DIR..."

  # Ask once if not using --force
  if [[ "$*" != *"--force"* ]]; then
    read -rp "🛠️  Do you want to update the Firing Range scripts in $BIN_DIR? (y/n): " confirm_all
    if [[ ! "$confirm_all" =~ ^[Yy]$ ]]; then
      log "User declined to update scripts."
      return
    fi
  fi

  for script in "${SCRIPTS[@]}"; do
    if [[ -f "$script" ]]; then
      if [[ "$PWD/$script" -ef "$BIN_DIR/$script" ]]; then
        log "⚠️  '$script' already exists. Overwriting."
      fi
      cp -f "$script" "$BIN_DIR/"
      echo "$BIN_DIR/$script" >> "$ROLLBACK_FILE"
    else
      log "⚠️  Skipping missing script: $script"
    fi
  done

  chmod +x "$BIN_DIR"/*.sh

  for script in "${SCRIPTS[@]}"; do
    if [[ ! -x "$BIN_DIR/$script" ]]; then
      log "❌ Script $script was not copied or is not executable."
      exit 1
    fi
  done

  log "Scripts installed and made executable."
}
}


create_symlinks() {
  if [[ "$*" == *"--force"* ]]; then
    log "⚙️  --force enabled: creating symlinks without prompt."
    auto_link=true
  else
    read -rp "🛠️  Do you want to install launchers into your \$PATH? (y/n): " answer
    if [[ "$answer" =~ ^[Yy]$ ]]; then
      auto_link=true
    else
      log "User chose not to create symlinks."
      return
    fi
  fi

  if [[ "$auto_link" == true ]]; then
    for path_dir in ${PATH//:/ }; do
      if [[ -w "$path_dir" ]]; then
        log "Using $path_dir for symlinks."
        for script in "$BIN_DIR"/*.sh; do
          base_name=$(basename "$script" .sh)
          ln -sf "$script" "$path_dir/$base_name"
          echo "$path_dir/$base_name" >> "$ROLLBACK_FILE"
          log "🔗 Linked $base_name to $path_dir/$base_name"
        done
        return
      fi
    done
    log "❌ No writable directory found in \$PATH. Skipping symlink creation."
  fi
}

install_from_github() {
  log "🔄 Downloading latest scripts from GitHub..."
  if ! git clone --depth=1 https://github.com/unspecific/nmap-firing-range.git temp_firing_range; then
    log "❌ Failed to clone from GitHub. Check your internet connection."
    exit 1
  fi
  for script in "${SCRIPTS[@]}"; do
    if [[ -f "temp_firing_range/$script" ]]; then
      cp "temp_firing_range/$script" .
    else
      log "⚠️  Missing expected script in repo: $script"
    fi
  done
  rm -rf temp_firing_range
  log "✅ Scripts downloaded and synced from GitHub."

  if [[ -f "setup_lab.sh" ]]; then
    exec ./setup_lab.sh --skip-update "$@"
  fi
}

uninstall() {
  echo "🚨 Uninstalling Firing Range..."
  read -rp "💾 Do you want to back up the session logs before uninstalling? (y/n): " backup_logs
  if [[ "$backup_logs" =~ ^[Yy]$ ]]; then
    BACKUP_FILE="/tmp/firing-range-logs-$(date +%Y%m%d%H%M%S).tar.gz"
    tar -czf "$BACKUP_FILE" -C "$LOG_DIR" . && echo "📦 Logs backed up to $BACKUP_FILE"
  fi

  if [[ -f "$ROLLBACK_FILE" ]]; then
    while read -r line; do
      if [[ -e "$line" ]]; then
        log "🗑️  Removing $line"
        rm -f "$line"
      fi
    done < "$ROLLBACK_FILE"
  fi
  log "🧹 Removing directory: $INSTALL_DIR"
  rm -rf "$INSTALL_DIR"
  log "✅ Uninstallation complete."
  exit 0
}

### MAIN ###
if [[ "${1:-}" == "--uninstall" ]]; then
  uninstall
elif [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  show_help
fi

if [[ "$(pwd)" == "$INSTALL_DIR"* ]]; then
  echo "⚠️  Please run setup_lab.sh from outside $INSTALL_DIR to avoid overwrite conflicts."
  exit 1
fi

mkdir -p "$LOG_DIR"
log "🚀 Starting Firing Range setup..."

check_dependencies

if [[ "$*" == *"--skip-update"* ]]; then
  github_choice="n"
elif [[ "${1:-}" == "--no-prompt" ]]; then
  github_choice="n"
else
  read -rp "🌐 Do you want to download the latest version from GitHub? (y/n): " github_choice
fi

if [[ "$github_choice" =~ ^[Yy]$ ]]; then
  install_from_github "$@"
else
  log "📁 Using scripts in current local directory."
fi

create_directories
install_scripts
create_symlinks

log "✅ Firing Range setup completed successfully."
log "📁 Scripts installed to: $BIN_DIR"
log "📄 Symlinks (if created) are available in PATH directories."
log "📝 Setup log saved at: $LOGFILE"
echo "✅ Setup complete. You can now run 'launch_lab' or 'cleanup_lab'."
