#!/bin/bash

# service_emulator.sh - lightweight service emulation script
# Emulates basic interaction for text-based protocols (FTP, SMTP, etc.) for testing and Nmap banner detection
# Usage: ./service_emulator.sh <service> <flag>

# Allow CLI args to override env vars
if [[ -n "$1" ]]; then SERVICE="$1"; fi
if [[ -n "$2" ]]; then FLAG="$2"; fi

SERVICE="${SERVICE:-}"
FLAG="${FLAG:-}"
PORT="$PORT"

if [[ -z "$SERVICE" || -z "$FLAG" ]]; then
  echo "Usage: $0 <service> <flag>"
  exit 1
fi

PORT=""

generate_banner() {
  case "$SERVICE" in
    ftp) echo -e "220 (Fake FTP Server)\r" ;;
    smtp) echo -e "220 fake-smtp.local ESMTP Postfix\r" ;;
    telnet) echo -e "\nWelcome to Fake Telnet Service\nLogin: " ;;
    ssh) echo -e "SSH-2.0-OpenSSH_8.2p1 Ubuntu-4ubuntu0.3\r" ;;
    pop3) echo -e "+OK POP3 fake-server ready\r" ;;
    imap) echo -e "* OK IMAP4rev1 Fake Server ready\r" ;;
    http) echo -n "" ;;  # HTTP handled separately
    *) echo -e "Fake $SERVICE Service Ready\r" ;;
  esac
}

handle_http() {
  REQUEST=""
  while IFS=$'\r' read -r line && [[ -n "$line" ]]; do
    REQUEST+="$line"$'\n'
  done

  METHOD=$(echo "$REQUEST" | head -n1 | awk '{print $1}')
  URI=$(echo "$REQUEST" | head -n1 | awk '{print $2}')
  VERSION=$(echo "$REQUEST" | head -n1 | awk '{print $3}')
  VERSION="${VERSION:-HTTP/1.1}"

  case "$METHOD" in
    GET|HEAD)
      BODY="<html><head><title>Fake Web</title></head><body><h1>Welcome to Emulated HTTP</h1><!-- FLAG: $FLAG --></body></html>"
      CONTENT_LENGTH=$(echo -n "$BODY" | wc -c)

      printf "%s 200 OK\r\n" "$VERSION"
      printf "Date: %s\r\n" "$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S GMT')"
      printf "Server: Apache/2.4.41 (Ubuntu)\r\n"
      printf "Content-Type: text/html; charset=UTF-8\r\n"
      printf "Content-Length: %d\r\n" "$CONTENT_LENGTH"
      printf "Connection: close\r\n"
      printf "\r\n"
      [[ "$METHOD" == "GET" ]] && printf "%s" "$BODY"
      ;;
    OPTIONS)
      printf "%s 200 OK\r\n" "$VERSION"
      printf "Allow: GET, HEAD, OPTIONS\r\n"
      printf "Content-Length: 0\r\n"
      printf "Connection: close\r\n"
      printf "\r\n"
      ;;
    POST)
      printf "%s 403 Forbidden\r\n" "$VERSION"
      printf "Content-Length: 0\r\n"
      printf "Connection: close\r\n"
      printf "\r\n"
      ;;
    *)
      printf "%s 405 Method Not Allowed\r\n" "$VERSION"
      printf "Allow: GET, HEAD, OPTIONS\r\n"
      printf "Content-Length: 0\r\n"
      printf "Connection: close\r\n"
      printf "\r\n"
      ;;
  esac
}

handle_telnet() {
  generate_banner
  read -r USER_INPUT
  echo "Password: "
  read -r PASS_INPUT
  if [[ "$USER_INPUT" == "guest" && "$PASS_INPUT" == "guest" ]]; then
    echo "Access granted. FLAG: $FLAG"
  else
    echo "Login failed."
  fi
}

handle_ftp() {
  echo -e "220 Fake FTP server ready"
  while read -r line; do
    case "$line" in
      USER*)
        echo "331 Please specify the password."
        ;;
      PASS*)
        echo "230 Login successful."
        ;;
      SYST)
        echo "215 UNIX Type: L8"
        ;;
      FEAT)
        echo "211-Features:"; echo " EPRT"; echo " EPSV"; echo " MDTM"; echo " PASV"; echo " REST STREAM"; echo " SIZE"; echo " TVFS"; echo " UTF8"; echo "211 End"
        ;;
      PWD)
        echo "257 \"/\" is the current directory"
        ;;
      TYPE*)
        echo "200 Switching to Binary mode."
        ;;
      LIST)
        echo "150 Here comes the directory listing."
        echo "-rw-r--r-- 1 root root 42 Jan 1 00:00 FLAG.txt"
        echo "226 Directory send OK."
        ;;
      RETR*)
        echo "150 Opening BINARY mode data connection."
        echo "FLAG: $FLAG"
        echo "226 Transfer complete."
        ;;
      QUIT)
        echo "221 Goodbye."
        break
        ;;
      *)
        echo "500 Unknown command."
        ;;
    esac
  done
}

handle_smtp() {
  echo "220 fake-smtp.local ESMTP Postfix"
  while read -r line; do
    case "$line" in
      HELO*|EHLO*)
        echo "250 Hello $(hostname), pleased to meet you"
        ;;
      MAIL\ FROM:*)
        echo "250 OK"
        ;;
      RCPT\ TO:*)
        echo "250 Accepted"
        ;;
      DATA)
        echo "354 End data with <CR><LF>.<CR><LF>"
        echo "Subject: Test Message"
        echo ""
        echo "This is a test SMTP message."
        echo "FLAG: $FLAG"
        echo "."
        echo "250 OK: queued"
        ;;
      QUIT)
        echo "221 Bye"
        break
        ;;
      *)
        echo "500 Unrecognized command"
        ;;
    esac
  done
}

handle_ssh() { generate_banner; cat; }
handle_pop3() {
  echo -e "+OK POP3 fake-server ready"
  while read -r line; do
    case "$line" in
      USER*)
        echo "+OK User accepted"
        ;;
      PASS*)
        echo "+OK Logged in."
        ;;
      STAT)
        echo "+OK 1 512"
        ;;
      LIST)
        echo "+OK 1 messages (512 octets)"
        echo "1 512"
        echo "."
        ;;
      RETR*)
        echo "+OK Message follows"
        echo "Subject: Test Message"
        echo ""
        echo "This is a test message."
        echo "FLAG: $FLAG"
        echo "."
        ;;
      QUIT)
        echo "+OK Bye"
        break
        ;;
      *)
        echo "-ERR Unknown command"
        ;;
    esac
  done
}
handle_imap() {
  echo "* OK IMAP4rev1 FakeServer ready"

  while read -r line; do
    tag=$(echo "$line" | awk '{print $1}')
    cmd=$(echo "$line" | awk '{print toupper($2)}')

    case "$cmd" in
      LOGIN)
        echo "$tag OK LOGIN completed"
        ;;
      CAPABILITY)
        echo "* CAPABILITY IMAP4rev1 STARTTLS AUTH=PLAIN"
        echo "$tag OK CAPABILITY completed"
        ;;
      LIST)
        echo "* LIST (\\Noselect) \"/\" \"INBOX\""
        echo "$tag OK LIST completed"
        ;;
      SELECT)
        echo "* FLAGS (\\Answered \\Flagged \\Deleted \\Seen \\Draft)"
        echo "* 1 EXISTS"
        echo "* 0 RECENT"
        echo "* OK [UIDVALIDITY 1] UIDs valid"
        echo "$tag OK [READ-WRITE] SELECT completed"
        ;;
      FETCH)
        echo "* 1 FETCH (BODY[HEADER] {102}"
        echo "Date: $(date -R)"
        echo "From: flagbot@example.com"
        echo "Subject: Your IMAP Flag"
        echo ""
        echo "FLAG: $FLAG"
        echo ")"
        echo "$tag OK FETCH completed"
        ;;
      LOGOUT)
        echo "* BYE Logging out"
        echo "$tag OK LOGOUT completed"
        break
        ;;
      *)
        echo "$tag BAD Unrecognized command"
        ;;
    esac
  done
}
handle_nntp() {
  echo "200 Fake NNTP server ready"

  while read -r line; do
    cmd=$(echo "$line" | awk '{print toupper($1)}')

    case "$cmd" in
      HELP)
        echo "100 Legal commands are:"
        echo "  HELP LIST GROUP ARTICLE QUIT"
        echo "."
        ;;
      LIST)
        echo "215 Newsgroups in form: group high low postable"
        echo "comp.fake.flag 001 001 y"
        echo "."
        ;;
      GROUP)
        echo "211 1 1 1 comp.fake.flag"
        ;;
      ARTICLE)
        echo "220 1 <fakeflag@server> article retrieved"
        echo "From: flagbot@unspecific.com"
        echo "Newsgroups: comp.fake.flag"
        echo "Subject: Here is your flag"
        echo "Date: $(date -R)"
        echo ""
        echo "FLAG: $FLAG"
        echo "."
        ;;
      QUIT)
        break
        ;;
      *)
        echo "500 unknown command"
        ;;
    esac
  done
}
handle_generic() { generate_banner; cat; }
handle_restapi() {
  REQUEST=""
  while IFS=$'\r' read -r line && [[ -n "$line" ]]; do
    REQUEST+="$line"$'\n'
  done

  METHOD=$(echo "$REQUEST" | head -n1 | awk '{print $1}')
  URI=$(echo "$REQUEST" | head -n1 | awk '{print $2}')
  VERSION=$(echo "$REQUEST" | head -n1 | awk '{print $3}')
  VERSION="${VERSION:-HTTP/1.1}"

  case "$METHOD $URI" in
    "GET /api/flag")
      BODY="{\"flag\": \"$FLAG\"}"
      CODE="200 OK"
      ;;
    "GET /api/status")
      BODY="{\"status\": \"online\", \"uptime\": \"$(uptime -p | sed 's/up //')\"}"
      CODE="200 OK"
      ;;
    "GET /api/help")
      BODY="{\"routes\": [\"/api/flag\", \"/api/status\", \"/api/help\"]}"
      CODE="200 OK"
      ;;
    *)
      BODY="{\"error\": \"Not Found\", \"method\": \"$METHOD\", \"uri\": \"$URI\"}"
      CODE="404 Not Found"
      ;;
  esac

  CONTENT_LENGTH=$(echo -n "$BODY" | wc -c)

  printf "%s %s\r\n" "$VERSION" "$CODE"
  printf "Content-Type: application/json\r\n"
  printf "Content-Length: %d\r\n" "$CONTENT_LENGTH"
  printf "Connection: close\r\n"
  printf "\r\n"
  printf "%s" "$BODY"
}

handle_session() {
  case "$SERVICE" in
    ftp) handle_ftp ;;
    smtp) handle_smtp ;;
    telnet) handle_telnet ;;
    ssh) handle_ssh ;;
    pop3) handle_pop3 ;;
    imap) handle_imap ;;
    http) handle_http ;;
    nntp) handle_nntp ;;
    restapi) handle_restapi ;;
    *) handle_generic ;;
  esac
}

case "$SERVICE" in
  ftp) PORT=21 ;;
  smtp) PORT=25 ;;
  telnet) PORT=23 ;;
  ssh) PORT=22 ;;
  pop3) PORT=110 ;;
  imap) PORT=143 ;;
  http) PORT=80 ;;
  nntp) PORT=119 ;;
  restapi) PORT=8080 ;;
  *) PORT=9999 ;;
esac

if [[ "$NC_LISTENER" != "true" ]]; then
  echo "[*] Launching with ncat on port $PORT for $SERVICE"
  if ss -ltn | grep -q ":$PORT"; then
    echo "❌ Port $PORT is already in use. Aborting."
    exit 1
  fi
  NC_LISTENER=true ncat -k -l "$PORT" --exec "/bin/bash $0 $SERVICE $FLAG" 2>/dev/null
else
  handle_session
fi
