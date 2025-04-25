#!/bin/bash
# ─── Emulator Metadata ─────────────────────────────────────────────────────
EM_PORT="tcp:79"               # The port this service listens on
EM_VERSION="6.99"               # Optional version identifier
EM_DAEMON="FakeFinger"
EM_DESC="Finger is a simple netwrk protocol for sharing personal information."  # Short description for listing output

# Read the username being requested (only one line for finger)
read username

# Optional logging
echo "[*] FINGER query received for: '$username'"

# Trim trailing whitespace
username=$(echo "$username" | xargs)

case "$username" in
    flaguser)
        echo -e "Login: flaguser\t\tName: Challenge User"
        echo -e "Directory: /home/flaguser\tShell: /bin/bash"
        echo -e "Plan:\n  $FLAG\n"
        ;;
    admin)
        echo -e "Login: admin\t\tName: System Administrator"
        echo -e "Directory: /root\tShell: /bin/bash"
        echo -e "Plan:\n  No flag here. Try harder.\n"
        ;;
    "")
        echo -e "No user specified. Try fingering a flagged user"
        ;;
    *)
        echo -e "User '$username' not found."
        ;;
esac
