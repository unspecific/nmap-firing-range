#!/bin/bash

# setup_lab.sh - Installer for the Firing Range Pentest Lab

APP="NFR-SetupLab"
VERSION=2.0


set -euo pipefail

# Ensure the script is run as root or with sudo
if [[ "$EUID" -ne 0 ]]; then
  echo "🔒 Root access required. Re-running with sudo..."
  exec sudo "$0" "$@"
fi

# Let's introduce ourselves
echo
echo " 🎩  $APP v$VERSION - Lee 'MadHat' Heath <lheath@unspecific.com>"

### CONFIG ###
INSTALL_DIR="/opt/firing-range"
BIN_DIR="$INSTALL_DIR/bin"
CONF_DIR="$INSTALL_DIR/conf"
TARGET_DIR="$INSTALL_DIR/target"
LOG_DIR="$INSTALL_DIR/logs"
LOGFILE="$LOG_DIR/setup.log"
SCRIPTS=("launch_lab.sh" "cleanup_lab.sh" "check_lab.sh" "setup_lab.sh")
ROLLBACK_FILE="$LOG_DIR/installed_files.txt"
NFR_GROUP="nfrlab"
FORCE=${FORCE:-false}
UNATTENDED=${UNATTENDED:-false}
AUTO_CONFIRM=${AUTO_CONFIRM:-false}

DEBUG=${DEBUG:-false}

### FUNCTIONS ###
log() {
  local mode="$1"
  shift
  local message=$*
  local log
  log="[$(date '+%Y-%m-%d %H:%M:%S')] [$APP v$VERSION] $message"

  if [[ "$mode" == "console" || "$DEBUG" == "true" ]]; then
    echo "$message"
  fi
  echo "$log" >> "$LOGFILE"
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
  log silent "Checking required dependencies..."
  local deps=(docker git curl)
  for dep in "${deps[@]}"; do
    if ! command -v "$dep" &>/dev/null; then
      log console "❌ Missing dependency: $dep"
      exit 1
    fi
  done

  # no GitHub auth required

  log silent "All dependencies satisfied."
}

create_directories() {
  log silent "Creating directory structure..."
  mkdir -p "$BIN_DIR" "$LOG_DIR" "$CONF_DIR" "$TARGET_DIR"
}

install_scripts() {
  log silent "Installing scripts to $BIN_DIR..."

  # Ask once if not using --force
  if [[ "$*" != *"--force"* ]]; then
    read -rp "🛠️  Do you want to update the Firing Range scripts in $BIN_DIR? (y/n): " confirm_all
    if [[ ! "$confirm_all" =~ ^[Yy]$ ]]; then
      log silent "User declined to update scripts."
      return
    fi
  fi

  for script in "${SCRIPTS[@]}"; do
    script="bin/${script}"
    if [[ -f "$script" ]]; then
      if [[ "$PWD$script" -ef "$BIN_DIR/$script" ]]; then
        log console "⚠️  '$script' already exists. Overwriting."
      fi
      cp -f "$script" "$BIN_DIR/"
      echo "$BIN_DIR/$script" >> "$ROLLBACK_FILE"
    else
      log console "⚠️  Skipping missing script: $script"
    fi
  done

  log silent "Making scripts executable"
  chmod +x "$BIN_DIR"/*.sh

  for script in "${SCRIPTS[@]}"; do
    if [[ ! -x "$BIN_DIR/$script" ]]; then
      log console "❌ Script $script was not copied or is not executable."
      exit 1
    fi
  done

  log silent "Scripts installed and made executable."
}

create_symlinks() {
  if [[ "$*" == *"--force"* ]]; then
    log console "⚙️  --force enabled: creating symlinks without prompt."
    auto_link=true
  else
    read -rp "🛠️  Do you want to install launchers into your \$PATH? (y/n): " answer
    if [[ "$answer" =~ ^[Yy]$ ]]; then
      auto_link=true
    else
      log silent "User chose not to create symlinks."
      return
    fi
  fi

  if [[ "$auto_link" == true ]]; then
    for path_dir in ${PATH//:/ }; do
      if [[ -w "$path_dir" ]]; then
        log silent "Using $path_dir for symlinks."
        for script in "$BIN_DIR"/*.sh; do
          base_name=$(basename "$script" .sh)
          target="$path_dir/$base_name"

          if [[ -L "$target" || -e "$target" ]]; then
            log console "⚠️  Skipping $target — already exists."
            continue
          fi

          ln -s "$script" "$target"
          echo "$target" >> "$ROLLBACK_FILE"
          log console "🔗 Linked $base_name to $target"
        done
        return
      fi
    done
    log console "❌ No writable directory found in \$PATH. Skipping symlink creation."
  fi
}


install_from_github() {
  log console "🔄 Downloading latest scripts from GitHub..."
  if ! git clone --depth=1 https://github.com/unspecific/nmap-firing-range.git temp_firing_range; then
    log console "❌ Failed to clone from GitHub. Check your internet connection."
    exit 1
  fi
  for script in "${SCRIPTS[@]}"; do
    if [[ -f "temp_firing_range/$script" ]]; then
      cp "temp_firing_range/$script" .
    else
      log console "⚠️  Missing expected script in repo: $script"
    fi
  done
  rm -rf temp_firing_range
  log console "✅ Scripts downloaded and synced from GitHub."
  log console "♻️ relaunching setup_lab to mke sure it is the latest version."

  if [[ -f "setup_lab.sh" ]]; then
    exec ./setup_lab.sh --skip-update "$@"
  fi
}

install_conf_dir() {
  log console "📁 Installing conf directory..."
  local target_dir="$INSTALL_DIR/$CONF_DIR"

  mkdir -p "$target_dir" || { log console "❌ Failed to create conf directory"; exit 1; }

  cp -r ./conf/* "$target_dir/" || {
    log console "❌ Failed to copy configuration files"
    exit 1
  }

  log console "✅ Configuration files installed to $target_dir"
}

# install the assets to build target containers
install_target_dir() {
  log console "📁 Installing target directory..."

  mkdir -p "$TARGET_DIR" || {
    log console "❌ Failed to create target directory"
    exit 1
  }

  cp -r ./target/* "$TARGET_DIR/" || {
    log console "❌ Failed to copy target service files"
    exit 1
  }

  log console "✅ Target services installed to $TARGET_DIR"
}

setup_group_access() {
  log console "👥 Configuring group access and permissions..."

  # Force or unattended install? No prompt.
  if [[ "$FORCE" == true || "$UNATTENDED" == true ]]; then
    AUTO_CONFIRM=true
  fi

  if [[ "$AUTO_CONFIRM" != true ]]; then
    read -rp "❓ Create a shared group '${NFR_GROUP}' for lab participants? (y/n): " confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || {
      log console "❌ Skipping group creation and access setup."
      return
    }
  fi

  if ! getent group $NFR_GROUP > /dev/null; then
    log console "📦 Creating group '${NFR_GROUP}'..."
    groupadd $NFR_GROUP
  else
    log console "ℹ️ Group '${NFR_GROUP}' already exists."
  fi

  log console "🔧 Setting permissions for $INSTALL_DIR..."
  chown -R root:"$NFR_GROUP" "$INSTALL_DIR"
  find "$INSTALL_DIR" -type d -exec chmod 755 {} +
  find "$INSTALL_DIR" -type f -exec chmod 644 {} +
  find "$INSTALL_DIR/bin" "$INSTALL_DIR/target/services" -type f -name "*.sh" -exec chmod 755 {} +

  local real_user="${SUDO_USER:-$USER}"
  if id -nG "$real_user" | grep -qw "$NFR_GROUP"; then
    log console "✅ User '$real_user' is already a member of '${NFR_GROUP}'."
  else
    log console "👤 Adding user '$real_user' to group '${NFR_GROUP}'..."
    usermod -aG "$NFR_GROUP" "$real_user"
    log console "🔄 Log out and back in to apply group changes."
  fi
}

uninstall() {
  LOGFILE="nfr_uninstall.log"
  if [[ ! -d "$INSTALL_DIR" || -z "$(ls -A "$INSTALL_DIR" 2>/dev/null)" ]]; then
    log console "❌ No installation detected in $INSTALL_DIR. Nothing to uninstall."
    exit 1
  fi

  log console "🚨 Uninstalling Firing Range..."
  if [[ -d "$LOG_DIR" ]]; then
    read -rp "💾 Do you want to back up the session logs before uninstalling? (y/n): " backup_logs
    if [[ "$backup_logs" =~ ^[Yy]$ ]]; then
      log silent "Backing up existing logs"
      BACKUP_FILE="/tmp/firing-range-logs-$(date +%Y%m%d%H%M%S).tar.gz"
      tar -czf "$BACKUP_FILE" -C "$LOG_DIR" . && echo "📦 Logs backed up to $BACKUP_FILE"
    fi
  else
    log silent "ℹ️  No log directory found. Skipping log backup."
  fi


  if [[ -f "$ROLLBACK_FILE" ]]; then
    while read -r line; do
      if [[ -L "$line" ]]; then
        log console "🔗 Removing symlink: $line"
        rm -f "$line"
      elif [[ -e "$line" ]]; then
        log console "🗑️  Removing file: $line"
        rm -f "$line"
      fi
    done < "$ROLLBACK_FILE"
  fi

  log console "🧹 Removing directory: $INSTALL_DIR"
  rm -rf "$INSTALL_DIR"

  if getent group "$NFR_GROUP" &>/dev/null; then
    log console "👥 Removing group: $NFR_GROUP"
    groupdel "$NFR_GROUP"
  fi

  log console "✅ Uninstallation complete."
  exit 0
}

### MAIN ###
if [[ "${1:-}" == "--uninstall" ]]; then
  uninstall
  exit 0
elif [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  show_help
  exit 0
fi

if [[ -d "$INSTALL_DIR" ]]; then
  echo " 🚧  Existing installation detected at $INSTALL_DIR."
  echo "     We can update the existing installation. Logs/sessions will not be touched"
  read -rp "Do you want to update the existing installation? (y/n): " response
  if [[ ! "$response" =~ ^[Yy]$ ]]; then
    echo " ❌  Installation aborted."
    exit 1
  fi
fi

if [[ "$(pwd)" == "$INSTALL_DIR"* ]]; then
  echo "⚠️  Please run setup_lab.sh from outside $INSTALL_DIR to avoid overwrite conflicts."
  exit 1
fi

mkdir -p "$LOG_DIR"
log silent "$APP v$VERSION initializing..."
log console "🚀 Starting $APP v$VERSION..."

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
  log console "📁 Using scripts in current local directory."
fi

create_directories "$@"
install_scripts "$@"
install_conf_dir
install_target_dir
setup_group_access
create_symlinks "$@"

log console "✅ Firing Range setup completed successfully."
log console "📁 Scripts installed to: $BIN_DIR"
log console "📄 Symlinks (if created) are available in PATH directories."
log console "📝 Setup log saved at: $LOGFILE"
log console "✅ Setup complete. You can now run 'launch_lab' or 'cleanup_lab'."
echo