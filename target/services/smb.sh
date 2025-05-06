#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# ─── Emulator Metadata ─────────────────────────────────────────────────────
EM_PORT="tcp:445 tcp:1445:tls"        # SMB ports (text-mode)
EM_VERSION="1.0"                      # Fake SMB version
EM_DAEMON="FakeSMBd"                  # Daemon name
EM_DESC="Text-mode SMB emulator (LIST/GET)"  # Description

# Share and files
SHARE_NAME="flagshare"
FLAG_FILE="flag.txt"
FLAG_CONTENT="${FLAG:-flag{default-smb-flag}}"

# Banner
echo "$EM_DAEMON v$EM_VERSION ready"

echo "Type HELP for commands"

# Main loop: simple text commands
while IFS= read -r line; do
    cmd=${line%% *}
    arg=${line#* }

    case "${cmd^^}" in
        HELP)
            echo "Supported commands:"
            echo "  LIST"          # list shares/files
            echo "  GET <filename>"
            echo "  QUIT"
            ;;
        LIST)
            # Enumerate share or files
            if [[ "$arg" == "" ]]; then
                echo "Shares: $SHARE_NAME"
            else
                # LIST <share>
                if [[ "$arg" == "$SHARE_NAME" ]]; then
                    echo "Files in $SHARE_NAME:"
                    echo "  $FLAG_FILE"
                else
                    echo "ERROR: Unknown share '$arg'"
                fi
            fi
            ;;
        GET)
            if [[ "$arg" == "$FLAG_FILE" || "$arg" == "$SHARE_NAME/$FLAG_FILE" ]]; then
                echo "$FLAG_CONTENT"
            else
                echo "ERROR: File not found '$arg'"
            fi
            ;;
        QUIT)
            echo "Goodbye"
            break
            ;;
        *)
            echo "ERROR: Unknown command '$cmd'"
            ;;
    esac
done

# pause for scanners
sleep 1
