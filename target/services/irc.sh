#!/bin/bash

# ─── Emulator Metadata ─────────────────────────────────────────────────────
EM_PORT="TCP:6667 tcp:6697:tls"               # The port this service listens on
EM_VERSION="2.6"               # Optional version identifier
EM_DAEMON="FakeIRC"
EM_DESC="IRCd server"  # Short description for listing output


echo -e ":irc.fakecorp.net 001 user :Welcome to $EM_DAEMON!\r"
echo -e ":irc.fakecorp.net 002 user :Your host is $EM_DAEMON $EM_VERSION, running on Bash\r"
echo -e ":irc.fakecorp.net 003 user :This server was created for you\r"
echo -e ":irc.fakecorp.net 004 user $EM_DAEMON $EM_VERSION o o\r"
echo -e ":irc.fakecorp.net 375 user :- irc.fakecorp.net Message of the Day -\r"
echo -e ":irc.fakecorp.net 372 user :- Welcome to the challenge.\r"
echo -e ":irc.fakecorp.net 372 user :- $FLAG\r"
echo -e ":irc.fakecorp.net 376 user :End of /MOTD command.\r"

joined=false

while IFS= read -r line; do
    echo "[*] IRC received: $line"

    if [[ "$line" =~ ^NICK ]]; then
        echo -e ":irc.fakecorp.net 001 ${line#NICK } :Welcome\r"
    elif [[ "$line" =~ ^USER ]]; then
        echo -e ":irc.fakecorp.net 001 user :Login accepted\r"
    elif [[ "$line" =~ ^JOIN ]]; then
        channel=$(echo "$line" | cut -d' ' -f2)
        echo -e ":user!user@host JOIN $channel\r"
        echo -e ":irc.fakecorp.net 332 user $channel :Welcome to $channel\r"
        echo -e ":irc.fakecorp.net 333 user $channel admin 1234567890\r"
        echo -e ":irc.fakecorp.net NOTICE user $FLAG\r"
        joined=true
    elif [[ "$line" =~ ^PRIVMSG ]]; then
        echo -e ":irc.fakecorp.net NOTICE user :Sorry, no DMs allowed.\r"
    elif [[ "$line" =~ ^QUIT ]]; then
        echo -e ":irc.fakecorp.net ERROR :Closing Link: user (Quit)\r"
        break
    else
        echo -e ":irc.fakecorp.net 421 user ${line%% *} :Unknown command\r"
    fi
done
