#!/bin/bash

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
        echo -e "Plan:\n  flag{fingered-the-right-user}\n"
        ;;
    admin)
        echo -e "Login: admin\t\tName: System Administrator"
        echo -e "Directory: /root\tShell: /bin/bash"
        echo -e "Plan:\n  No flag here. Try harder.\n"
        ;;
    "")
        echo -e "No user specified. Try: finger flaguser"
        ;;
    *)
        echo -e "User '$username' not found."
        ;;
esac
