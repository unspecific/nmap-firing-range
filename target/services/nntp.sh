#!/bin/bash

# ─── Emulator Metadata ─────────────────────────────────────────────────────
EM_PORT="tcp:119 tcp:563:tls"               # The port this service listens on
EM_VERSION="3.1"               # Optional version identifier
EM_DESC="NNTP with brute force"  # Short description for listing output
EM_DAEMON="FakeNNTP"

echo -e "200 $HOSTNAME $EM_DAEMON/$EM_VERSION server ready\r"

authenticated=false
correct_user="$USERNAME"
correct_pass="$PASSWORD"
flag_group="alt.ctf.challenge"
flag_article_id="<1337@$HOSTNAME>"

while IFS= read -r line; do
    cmd=$(echo "$line" | awk '{print $1}')
    arg=$(echo "$line" | cut -d' ' -f2-)

    case "$cmd" in
        HELP)
            echo -e "100 Help text follows\r"
            echo -e "Supported: HELP, LIST, GROUP, ARTICLE, QUIT, AUTHINFO\r"
            echo -e ".\r"
            ;;
        AUTHINFO)
            if [[ "$arg" == "USER "* ]]; then
                user="${arg#USER }"
                echo -e "381 Password required\r"
            elif [[ "$arg" == "PASS "* ]]; then
                pass="${arg#PASS }"
                if [[ "$user" == "$correct_user" && "$pass" == "$correct_pass" ]]; then
                    authenticated=true
                    echo -e "281 Authentication accepted\r"
                else
                    echo -e "481 Authentication failed\r"
                fi
            else
                echo -e "501 Syntax error\r"
            fi
            ;;
        LIST)
            echo -e "215 Newsgroups follow\r"
            echo -e "$flag_group 1 1 y\r"
            echo -e ".\r"
            ;;
        GROUP)
            if [[ "$arg" == "$flag_group" ]]; then
                echo -e "211 1 1 1 $flag_group\r"
            else
                echo -e "411 No such newsgroup\r"
            fi
            ;;
        ARTICLE)
            echo -e "220 1 $flag_article_id article retrieved\r"
            echo -e "From: challenge@nfr.lab\r"
            echo -e "Subject: Welcome\r"
            echo -e "Newsgroups: $flag_group\r"
            echo -e "Message-ID: $flag_article_id\r"
            echo -e "\r"
            echo -e "Here's your flag:\r"
            echo -e "$FLAG\r"
            echo -e ".\r"
            ;;
        QUIT)
            echo -e "205 closing connection - goodbye!\r"
            exit 0
            ;;
        *)
            echo -e "500 Command not recognized\r"
            ;;
    esac
done
