#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# ─── Emulator Metadata ─────────────────────────────────────────────────────
EM_PORT="tcp:79"               # The port this service listens on
EM_VERSION="6.99"              # Optional version identifier
EM_DAEMON="FakeFinger"
EM_DESC="Simple service sharing personal information."  # Short description

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
        echo -e "Plan:\n  > Read the flag. Celebrate!\n"
        ;;
    admin)
        echo -e "Login: admin\t\tName: System Administrator"
        echo -e "Directory: /root\tShell: /bin/bash"
        echo -e "Plan:\n  > Pretend to be busy. Nothing to see here.\n"
        ;;
    root)
        echo -e "Login: root\t\tName: The Almighty Root"
        echo -e "Directory: /root\tShell: /bin/bash"
        echo -e "Plan:\n  > World domination in progress.\n"
        ;;
    guest)
        echo -e "Login: guest\t\tName: Guest User"
        echo -e "Directory: /home/guest\tShell: /bin/sh"
        echo -e "Plan:\n  > Just browsing. Buzz off.\n"
        ;;
    alice)
        echo -e "Login: alice\t\tName: Alice Wonderland"
        echo -e "Directory: /home/alice\tShell: /bin/zsh"
        echo -e "Plan:\n  > Going down the rabbit hole.\n"
        ;;
    bob)
        echo -e "Login: bob\t\tName: Bob Builder"
        echo -e "Directory: /home/bob\tShell: /bin/bash"
        echo -e "Plan:\n  > Can we fix it? Yes we can!\n"
        ;;
    charlie)
        echo -e "Login: charlie\t\tName: Chuck Norris"
        echo -e "Directory: /home/charlie\tShell: /bin/bash"
        echo -e "Plan:\n  > Roundhouse kicking servers.\n"
        ;;
    nobody)
        echo -e "Login: nobody\t\tName: Nobody Special"
        echo -e "Directory: /home/nobody\tShell: /bin/false"
        echo -e "Plan:\n  > Do nothing, go nowhere.\n"
        ;;
    www-data)
        echo -e "Login: www-data\t\tName: Web Service"
        echo -e "Directory: /var/www\tShell: /usr/sbin/nologin"
        echo -e "Plan:\n  > Serving pages 24/7.\n"
        ;;
    test)
        echo -e "Login: test\t\tName: Test Account"
        echo -e "Directory: /tmp/test\tShell: /bin/sh"
        echo -e "Plan:\n  > Testing, testing… 1, 2, 3.\n"
        ;;
    developer)
        echo -e "Login: developer\tName: Code Monkey"
        echo -e "Directory: /home/dev\tShell: /usr/bin/fish"
        echo -e "Plan:\n  > Ship features. Fix bugs. Repeat.\n"
        ;;
    "")
        echo -e "No user specified. Try fingering someone interesting!"
        ;;
    *)
        echo -e "User '$username' not found. Maybe try 'alice', 'bob', or 'charlie'?"
        ;;
esac
