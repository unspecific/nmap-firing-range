#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# ─── Emulator Metadata ─────────────────────────────────────────────────────
EM_PORT="tcp:6667 tcp:6697:tls"
EM_VERSION="2.6"
EM_DAEMON="FakeIRC"
EM_DESC="IRCd server with hidden paths to the flag"

HOST="irc.fakecorp.net"
FLAG="${FLAG:-flag{irc-secret-discovered}}"

client_nick=""
client_user=""
joined_channels=()

# Send a raw line to the client
send_line() { printf "%b\r\n" "$1"; }

# Numeric replies
send_numeric() {
  local num=$1; shift
  send_line ":$HOST $num ${client_nick:-*} $*"
}

greet() {
  send_numeric 001 "Welcome to $EM_DAEMON, ${client_nick:-newbie}"
  send_numeric 002 "Your host is $EM_DAEMON, running version $EM_VERSION"
  send_numeric 003 "This server was created just for you!"
  send_numeric 004 "$EM_DAEMON $EM_VERSION o o"
  send_numeric 375 "- Message of the Day -"
  send_numeric 372 "- Welcome to the challenge IRC!"
  send_numeric 372 "- Type /join #general or /join #secret"
  send_numeric 376 "End of MOTD"
}

handle_nick() {
  client_nick="$2"
  send_line ":$HOST NICK ${client_nick}"
}

handle_user() {
  client_user="$2"
  send_numeric 001 "User ${client_nick} registered as ${client_user}"
}

handle_join() {
  local chan="$2"
  joined_channels+=( "$chan" )
  send_line ":${client_nick}!${client_user}@${HOST} JOIN $chan"
  send_numeric 332 "$chan :Topic for $chan"
  send_numeric 333 "$chan admin  $(date +%s)"
  if [[ "$chan" == "#secret" ]]; then
    # reveal the flag quietly
    send_line ":$HOST NOTICE ${client_nick} :Pssst… the flag is $FLAG"
  else
    send_line ":$HOST NOTICE ${client_nick} :Welcome to $chan! Try /msg $HOST VERSION"
  fi
}

handle_privmsg() {
  local target="$2"; shift 2; local msg="$*"
  if [[ "$msg" =~ ^!flag$ ]] && [[ " ${joined_channels[*]} " =~ " #general " ]]; then
    # public flag hint
    send_line ":$HOST PRIVMSG #general :${client_nick}, the real flag is in #secret!"
  elif [[ "$target" == "$HOST" && "${msg^^}" =~ ^VERSION$ ]]; then
    # CTCP VERSION reveal
    send_line ":$HOST NOTICE ${client_nick} :\001VERSION $EM_DAEMON v$EM_VERSION — flag: $FLAG\001"
  else
    # echo back
    send_line ":$HOST PRIVMSG ${target} :I heard \"$msg\""
  fi
}

handle_ping() {
  send_line "PONG $HOST"
}

handle_quit() {
  send_line ":$HOST ERROR :Closing Link: ${client_nick} (Quit)"
  exit 0
}

main() {
  greet
  while IFS= read -r line || [[ -n "$line" ]]; do
    # Very basic parse
    cmd=${line%% *}
    args=${line#* }
    case "${cmd^^}" in
      NICK)   handle_nick $cmd $args ;;
      USER)   handle_user $cmd $args ;;
      JOIN)   handle_join $cmd $args ;;
      PRIVMSG) handle_privmsg $cmd $args ;;
      PING)   handle_ping ;;
      QUIT)   handle_quit ;;
      *)      send_numeric 421 "$cmd :Unknown command" ;;
    esac
  done
}

main
