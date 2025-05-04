#!/usr/bin/env bash
# setup_lab.sh - Installer for the Nmap Firing Range Pentest Lab

set -euo pipefail -o errtrace
trap 'cleanup; exit 1' ERR

APP="NFR-SetupLab"
VERSION="2.2"

# ─── Elevate to root if needed ────────────────────────────────────────
if [[ "$EUID" -ne 0 ]]; then
  echo "🔒 Root access required. Re-running with sudo..."
  exec sudo "$0" "$@"
fi

echo
echo " 🎩  $APP v$VERSION - Lee 'MadHat' Heath <lheath@unspecific.com>"
echo

# ─── Locate this script & repo root ──────────────────────────────────
SCRIPT_PATH="${BASH_SOURCE[0]}"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"    # e.g. …/nmap-firing-range/bin
REPO_ROOT="$(dirname "$SCRIPT_DIR")"                      # e.g. …/nmap-firing-range

# ─── Installation directories ────────────────────────────────────────
INSTALL_DIR="/opt/firing-range"
BIN_DIR="$INSTALL_DIR/bin"
CONF_DIR="$INSTALL_DIR/conf"
TARGET_DIR="$INSTALL_DIR/target"
LOG_DIR="$INSTALL_DIR/logs"
LOGFILE="$LOG_DIR/setup.log"
ROLLBACK_FILE="$INSTALL_DIR/installed_files.txt"
INSTALL_DIR_OVERRIDE=false

# ─── Defaults & flags ───────────────────────────────────────────────
FORCE=false
UNINSTALL=false
UPGRADE=false
NO_GRP=false
SKIP_GH=false
AUTO_CONFIRM=${AUTO_CONFIRM:-false}
UNATTENDED=${UNATTENDED:-false}
DEBUG=${DEBUG:-false}

NFR_GROUP="nfrlab"
REPO_URL="https://github.com/unspecific/nmap-firing-range.git"

# ─── Dependency lists ────────────────────────────────────────────────
DEPS=( bash git mktemp cp rm mv mkdir rmdir chmod chown find sort getent groupadd usermod id grep sudo )
LAB_DEPS=( docker grep shuf tee realpath openssl )
SCRIPTS=( launch_lab.sh cleanup_lab.sh check_lab.sh setup_lab.sh )

# ─── Rollback tracking ───────────────────────────────────────────────
TMP_ROLLBACK="$(mktemp)"
record() { echo "$1" >>"$TMP_ROLLBACK"; }


### FUNCTIONS ###
log() {
  local mode="$1"; shift
  local message="$*"
  local timestamp="[$(date '+%Y-%m-%d %H:%M:%S')]"
  local entry="$timestamp [$APP v$VERSION] $message"

  # always echo to console if asked
  if [[ "$mode" == "console" || "$DEBUG" == "true" ]]; then
    echo "$message"
  fi

  # ensure the log directory exists
  local logdir
  logdir="$(dirname "$LOGFILE")"
  mkdir -p "$logdir"

  # ensure the logfile itself exists (so that >> won’t fail on some filesystems)
  touch "$LOGFILE"

  echo "$entry" >> "$LOGFILE"
}

# ─── Help text ────────────────────────────────────────────────────────
show_help() {
  cat <<EOF
Firing Range Setup Script
Usage: $0 [OPTIONS]

Options:
  --help, -h            Show this help message and exit
  --uninstall           Uninstall all components and optionally backup logs
  --unattended          Run with no prompts (overwrite defaults)
  --upgrade             Download and install the latest scripts from GitHub
  --force               Overwrite all existing files without prompting
  --install-dir, --prefix DIR
                        Install into DIR instead of the default ($INSTALL_DIR)

This script installs or upgrades the Firing Range lab, verifies dependencies,
installs shell scripts, sets up permissions, and can pull the latest version
of the scripts from GitHub.
EOF
  exit 0
}

check_dependencies() {
  local missing=()
  for cmd in "${DEPS[@]}"; do
    if ! command -v "$cmd" &>/dev/null; then
      missing+=( "$cmd" )
    fi
  done
  if (( ${#missing[@]} )); then
    echo "❌   Missing installer dependencies: ${missing[*]}"
    exit 1
  fi
}

check_lab_dependencies() {
  local missing=()

  # check normal binaries
  for cmd in "${LAB_DEPS[@]}"; do
    if ! command -v "$cmd" &>/dev/null; then
      missing+=( "$cmd" )
    fi
  done

  # check for docker-compose *or* docker compose plugin
  if ! command -v docker-compose &>/dev/null; then
    if ! docker compose version &>/dev/null; then
      missing+=( "docker-compose (or 'docker compose')" )
    fi
  fi

  if (( ${#missing[@]} )); then
    echo "❌ Missing lab-runtime dependencies: ${missing[*]}"
    exit 1
  fi
}

create_directories() {
  log silent "Creating directory structure..."
  mkdir -p "$BIN_DIR" "$LOG_DIR" "$CONF_DIR" "$TARGET_DIR"
}

install_scripts() {
  log silent "Installing scripts to $BIN_DIR..."

  # start fresh rollback list
  : > "$TMP_ROLLBACK"

  # Prompt once unless forced or unattended
  if [[ "$FORCE" != true && "$UNATTENDED" != true ]]; then
    read -rp "🛠️  Do you want to update the Firing Range scripts in $BIN_DIR? (y/n): " confirm_all
    if [[ ! "$confirm_all" =~ ^[Yy]$ ]]; then
      log silent "User declined to update scripts."
      return
    fi
  else
    log silent "🛠️  Unattended/forced: updating scripts without prompt."
  fi

  mkdir -p "$BIN_DIR"

  for script_name in "${SCRIPTS[@]}"; do
    src="$SCRIPT_DIR/$script_name"
    dest="$BIN_DIR/$script_name"

    if [[ ! -f "$src" ]]; then
      log console "⚠️  Skipping missing script: $script_name"
      continue
    fi

    record "$dest"
    [[ -f "$dest" ]] && log console "⚠️  '$script_name' exists—overwriting."
    cp -f "$src" "$dest" || { log console "❌ Failed to copy $script_name"; exit 1; }
  done

  log silent "Making scripts executable..."
  for script_name in "${SCRIPTS[@]}"; do
    dest="$BIN_DIR/$script_name"
    [[ -f "$dest" ]] && chmod +x "$dest" && record "$dest"
  done

  # ——— HERE’S THE FIX ———
  # Deduplicate *the temp file* you’ve been writing to, not the missing permanent one
  sort -u -o "$TMP_ROLLBACK" "$TMP_ROLLBACK"

  # verify
  for script_name in "${SCRIPTS[@]}"; do
    dest="$BIN_DIR/$script_name"
    if [[ ! -x "$dest" ]]; then
      log console "❌  Script $script_name missing or not executable."
      exit 1
    fi
  done

  log silent "Scripts installed and executable."
}


create_symlinks() {
  local auto_link=false
  # decide if we prompt
  if [[ "$FORCE" == true || "$UNATTENDED" == true ]]; then
    auto_link=true
  else
    read -rp "🛠️  Install launchers into your \$PATH? (y/n): " answer
    [[ "$answer" =~ ^[Yy]$ ]] && auto_link=true || return
  fi

  local created_any=false
  IFS=: read -ra path_dirs <<< "$PATH"
  for path_dir in "${path_dirs[@]}"; do
    [[ -w "$path_dir" ]] || continue
    log silent "Using $path_dir for symlinks."

    for script in "$BIN_DIR"/*.sh; do
      local base_name target existing
      base_name=$(basename "$script" .sh)
      target="$path_dir/$base_name"

      if [[ -L "$target" ]]; then
        existing=$(readlink "$target")
        if [[ "$existing" != "$script" ]]; then
          log console "🔄 Updating symlink $target → $script"
          ln -sf "$script" "$target"
          record "$target"
          created_any=true
        else
          log silent "✅ $base_name already up-to-date."
        fi

      elif [[ -e "$target" ]]; then
        log console "⚠️  Skipping $target — exists and is not a symlink."

      else
        ln -s "$script" "$target"
        log console "🔗 Linked $base_name → $target"
        record "$target"
        created_any=true
      fi
    done

    # if we did anything here, stop; otherwise try next dir
    $created_any && return
    log console "⚠️  Nothing to do in $path_dir, trying next."
  done

  log console "❌ No writable \$PATH entry found or all links up-to-date; skipping."
}

# ─── This would be an Update routine ─────────────────────────────────
install_from_github() {
  clone_dir=$(mktemp -d -t nfr-XXXX)
  log console "🔄 Cloning into $clone_dir…"
  git clone --depth=1 "$REPO_URL" "$clone_dir" || {
    log console "❌ Git clone failed"; exit 1
  }
  log console "♻️ Relaunching installer from fresh clone…"
  exec "$clone_dir/setup_lab.sh" --skip-update "$@"
}

# ─── Rollback on error only ───────────────────────────────────────────
cleanup() {
  local exit_code=$?
  # only perform rollback if we errored *and* there’s something to roll back
  if (( exit_code != 0 )) && [[ -s "$TMP_ROLLBACK" ]]; then
    log console "⚠️  Failure detected (exit $exit_code), rolling back…"
    # remove in reverse order
    tac "$TMP_ROLLBACK" | while read -r path; do
      log console "🗑  Removing $path"
      rm -rf "$path" || log console "❌ Could not remove $path"
    done
    # also clean up any temp clone
    if [[ -n "${clone_dir:-}" && -d "$clone_dir" ]]; then
      log console "🗑  Removing temp clone $clone_dir"
      rm -rf "$clone_dir"
    fi
  fi

  # always clean up our rollback file
  rm -f "$TMP_ROLLBACK"
}

# trigger cleanup on script exit (both errors and normal), 
# but the function itself only rolls back on error
trap cleanup EXIT

# ─── Installing the CONF_DIR to LAB_DIR ─────────────────────────────────
install_conf() {
  log console "📁 Installing conf directory…"

  local src_dir="$REPO_ROOT/conf"
  if [[ ! -d "$src_dir" ]]; then
    log console "❌ Missing source conf directory at $src_dir"
    exit 1
  fi

  mkdir -p "$CONF_DIR"
  record "$CONF_DIR"                       # so we can remove it on rollback

  cp -r "$src_dir/"* "$CONF_DIR/" || {
    log console "❌ Failed to copy configuration files"
    exit 1
  }

  log console "✅ Configuration files installed to $CONF_DIR"
}

# ─── Installing the TARGET_DIR to LAB_DIR ─────────────────────────────────
install_target() {
  log console "📁 Installing target directory…"

  local src_dir="$REPO_ROOT/target"
  if [[ ! -d "$src_dir" ]]; then
    log console "❌ Missing source target directory at $src_dir"
    exit 1
  fi

  mkdir -p "$TARGET_DIR"
  record "$TARGET_DIR"                     # so we can remove it on rollback

  cp -r "$src_dir/"* "$TARGET_DIR/" || {
    log console "❌ Failed to copy target services"
    exit 1
  }

  log console "✅ Target services installed to $TARGET_DIR"
}

# ─── Creating the NFR_GROUP and preparing LABDIR ──────────────────────────
setup_group_access() {
  log console "👥 Configuring group access and permissions…"

  # determine whether to prompt or auto-confirm
  local confirm
  if [[ "$FORCE" == true || "$UNATTENDED" == true ]]; then
    confirm="Y"
    log silent "🛠️  ${UNATTENDED:+Unattended/}${FORCE:+Forced}: auto-confirming group creation."
  else
    read -rp "❓ Create a shared group '${NFR_GROUP}' for lab participants? (y/n): " confirm
  fi

  # skip if the user explicitly said no
  if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    log console "❌ Skipping group creation and access setup."
    return
  fi

  # create the group if it doesn't exist
  if ! getent group "$NFR_GROUP" >/dev/null; then
    log console "📦 Creating group '${NFR_GROUP}'..."
    groupadd "$NFR_GROUP"
    NO_GRP=false
  else
    log console "ℹ️ Group '${NFR_GROUP}' already exists."
  fi

  # set ownership and permissions
  log console "🔧 Setting permissions for $INSTALL_DIR..."
  if [[ $NO_GRP != "true" ]]; then
    chown -R root:"$NFR_GROUP" "$INSTALL_DIR"
  else 
    chown -R root:nogroup "$INSTALL_DIR"
  fi
  find "$INSTALL_DIR" -type d -exec chmod 775 {} +
  find "$INSTALL_DIR" -type f -exec chmod 664 {} +
  find "$INSTALL_DIR/bin" "$INSTALL_DIR/target/services" -type f -name "*.sh" -exec chmod 775 {} +

  # add the real user to the group if not already a member
  local real_user="${SUDO_USER:-$USER}"
  if id -nG "$real_user" | grep -qw "$NFR_GROUP"; then
    log console "✅ User '$real_user' is already a member of '${NFR_GROUP}'."
  else
    log console "👤 Adding user '$real_user' to group '${NFR_GROUP}'..."
    usermod -aG "$NFR_GROUP" "$real_user"
    log console "🔄 Log out and back in to apply group changes."
  fi
}

# ─── Where is it?  WHERE IS IT?!? ─────────────────────────────────
determine_install_dir() {
  # 1) Default install-dir exists?
  if [[ -d "$INSTALL_DIR" ]]; then
    return
  fi

  # 2) If user explicitly overrode INSTALL_DIR, trust it (even if it doesn't exist yet)
  if [[ "${INSTALL_DIR_OVERRIDE:-false}" == true ]]; then
    return
  fi

  # 3) Prompt for the real install directory
  read -rp "❓ Install not found at $INSTALL_DIR. Enter install directory to remove (or leave blank to auto-detect project folder): " resp
  if [[ -n "$resp" ]]; then
    INSTALL_DIR="$resp"
    return
  fi

  # 4) Fallback: detect if we're in the source tree (./setup_lab.sh or cd bin/ && ./setup_lab.sh)
  local invoked_dir parent
  invoked_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  parent="$(dirname "$invoked_dir")"
  if [[ -d "$parent/bin" && -d "$parent/conf" && -d "$parent/target" ]]; then
    INSTALL_DIR="$parent"
    log console "ℹ️  No install at default; assuming project root = $INSTALL_DIR"
    return
  fi

  echo "❌ Could not locate an installation directory."
  exit 1
}


# ─── Kill it all, Burn it to the ground ─────────────────────────────────
uninstall() {
  determine_install_dir

  # recalc paths based on the resolved INSTALL_DIR
  BIN_DIR="$INSTALL_DIR/bin"
  CONF_DIR="$INSTALL_DIR/conf"
  TARGET_DIR="$INSTALL_DIR/target"
  LOG_DIR="$INSTALL_DIR/logs"
  LOGFILE="$LOG_DIR/setup.log"
  ROLLBACK_FILE="$INSTALL_DIR/installed_files.txt"

  log console "🗑  Uninstalling Firing Range from $INSTALL_DIR…"
  
  if [[ ! -d "$INSTALL_DIR" || -z "$(ls -A "$INSTALL_DIR" 2>/dev/null)" ]]; then
    log console "❌ No installation detected in $INSTALL_DIR. Nothing to uninstall."
    exit 1
  fi

  log console "🚨 Uninstalling Firing Range..."
  if [[ -d "$LOG_DIR" ]]; then
    if [[ "$FORCE" == true ]]; then
      backup_logs="y"
    else 
      read -rp " 💾  Do you want to back up the session logs before uninstalling? (y/n): " backup_logs
    fi
    if [[ "$backup_logs" =~ ^[Yy]$ ]]; then
      log silent "Backing up existing logs"
      BACKUP_FILE="/tmp/firing-range-logs-$(date +%Y%m%d%H%M%S).tar.gz"
      tar -czf "$BACKUP_FILE" -C "$LOG_DIR" . && echo "📦 Logs backed up to $BACKUP_FILE"
      log console " 💾  Backup file created $BACKUP_FILE.\r\nBe sure to move from /tmp/ otherwise they will be lost"
    fi
  else
    log silent " ℹ️  No log directory found. Skipping log backup."
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

# ─── Where can we install from ─────────────────────────────────
# $1 = mode: “installed” or “staged”
# $2 = optional dir–falls back to global INSTALL_DIR
check_local() {
  local mode="$1"
  local dir
  if [[ "$mode" == "staged" ]]; then
    dir="$(pwd)"
  else
    dir="${2:-$INSTALL_DIR}"
  fi

  case "$mode" in
    installed)
      # Installed if key dirs, setup script, and at least one target subdir exist
      [[ -d "$dir/bin" && -d "$dir/conf" && -d "$dir/target" ]] || return 1
      [[ -x "$dir/bin/setup_lab.sh" ]] || return 1
      # ensure either target/conf or target/services exists
      ([[ -d "$dir/target/conf" ]] || [[ -d "$dir/target/services" ]])
      ;;
    staged)
      # Staged if all scripts in SCRIPTS array are present and executable
      for script in "${SCRIPTS[@]}"; do
        if [[ ! -x "$dir/bin/$script" ]]; then
          return 1
        fi
      done
      ;;
    *)
      log console "❌  check_local: unknown mode '$mode'" >&2
      return 1
      ;;
  esac
}


### MAIN ###

# ─── Parse flags ─────────────────────────────────────────────────────
while (( $# )); do
  echo "Parse $1"
  case "$1" in
    --install-dir|--prefix)
      INSTALL_DIR="$2"
      INSTALL_DIR_OVERRIDE=true
      shift 2
      ;;
    --help|-h)        show_help ;;
    --uninstall)      UNINSTALL=true; shift ;;
    --skip-upgrade)   SKIP_GH=true; shift ;;
    --unattended)     UNATTENDED=true; shift ;;
    --upgrade)        UPGRADE=true;    shift ;;
    --force)          FORCE=true;      shift ;;
    --*)  # any other long option is an error
      echo "❌ Unknown option: $1" >&2
      show_help
      exit 1
      ;;
    -*)  # preserve single‐letter flags for getopts
      break
      ;;
  esac
done

# ─── Re-calc dependent paths only if INSTALL_DIR was overridden ─────
if [[ "$INSTALL_DIR_OVERRIDE" == true ]]; then
  BIN_DIR="$INSTALL_DIR/bin"
  CONF_DIR="$INSTALL_DIR/conf"
  TARGET_DIR="$INSTALL_DIR/target"
  LOG_DIR="$INSTALL_DIR/logs"
  LOGFILE="$LOG_DIR/setup.log"
  ROLLBACK_FILE="$INSTALL_DIR/installed_files.txt"
fi

if getent group "$NFR_GROUP" >/dev/null 2>&1; then
  log console " ✅  Group ‘$NFR_GROUP’ exists."
else
  log console " ❌  Group ‘$NFR_GROUP’ does not exist."
  log console " Please make sure nmap firing range is properly installed."
  NO_GRP=true
fi

# ─── One-off commands ────────────────────────────────────────────────
if [[ "$UNINSTALL" == true ]]; then
  uninstall
  exit 0
elif [[ "$UPGRADE" == true ]]; then
  log console "🔄 Upgrade requested: pulling from GitHub…"
  install_from_github "$@"
  exit 0
fi

# ─── Dependency checks ───────────────────────────────────────────────
check_dependencies
check_lab_dependencies

if [[ "$(pwd)" == "$INSTALL_DIR"* ]]; then
  echo "⚠️  Please run setup_lab.sh from outside $INSTALL_DIR to avoid overwrite conflicts."
  exit 1
fi

mkdir -p "$LOG_DIR"
log silent "$APP v$VERSION initializing..."
log console "🚀 Starting $APP v$VERSION..."


# ─── Detect existing install & scripts ───────────────────────────────
# ─── Installation Decision Logic ─────────────────────────────────────────
INSTALL_MODE=""



# 1) Existing installation? Prompt to update
log console "  Checking for existing installation in $INSTALL_DIR"
if check_local installed "$INSTALL_DIR" && [[ "$UPGRADE" != true && "$SKIP_GH" != true ]]; then
  log console " 🚧  Installation found at $INSTALL_DIR."
  if [[ "$UNATTENDED" == true || "$SKIP_GH" == true]]; then
    log console " ✅  Unattended mode: can't install.\r\nUse --force to update existing install"
    exit 1
  else
    read -rp "Update existing installation? (y/n): " resp
    [[ "$resp" =~ ^[Yy]$ ]] && INSTALL_MODE="local" || log console " ⚠️  User does not want to update." && exit 1 
  fi
fi

# 2) Local staging install? If not updating, check for local scripts
log console "  Checking for install files $(pwd)"
if [[ $UPGRADE != "true" ]] && check_local staged; then
  log console " 🚧  Found staged files to install."
  if [[ "$UNATTENDED" == true || "$SKIP_GH" == true ]]; then
    INSTALL_MODE="local"
    log console " 📁  Unattended mode: installing from local scripts."
  else
    read -rp "Local scripts detected. Install from local directory? (y/n): " resp
    [[ "$resp" =~ ^[Yy]$ ]] && INSTALL_MODE="local"
  fi
fi

[[ "$SKIP_GH" == true ]]  && INSTALL_MODE=local

if [[ -z $INSTALL_MODE ]]; then
    read -rp "Do you want to install from GutHub (y/n): " resp
    [[ "$resp" =~ ^[Yy]$ ]] && INSTALL_MODE="github"
else 
  log console "Said no to local and GitHub Install"
  exit 1
fi


# 6) Execute mode
case "$INSTALL_MODE" in
  local)
    log console "🚀 Installing from local scripts..."
    # local install logic here
    ;;
  github)
    log console "🌐 Fetching and installing from GitHub..."
    install_from_github "$@"
    ;;
  *)
    log console "❌ No install mode selected; exiting."
    exit 1
    ;;
esac

create_directories "$@"
install_scripts "$@"
install_conf
install_target
setup_group_access
create_symlinks "$@"

log console "✅ Firing Range setup completed successfully."
log console "📁 Scripts installed to: $BIN_DIR"
log console "📄 Symlinks (if created) are available in PATH directories."
log console "📝 Setup log saved at: $LOGFILE"
log console "✅ Setup complete. You can now run 'launch_lab' or 'cleanup_lab'."
if [[ $NO_GRP != "true" ]]; then
  chgrp $NFR_GROUP $LOGFILE
fi
chmod 664 $LOGFILE
echo