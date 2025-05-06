#!/bin/bash

echo "Content-type: text/html"
echo ""

read POST_DATA

# URL decode function
urldecode() {
  local data="${1//+/ }"
  printf '%b' "${data//%/\\x}"
}

# Parse POST data into associative array
declare -A params
IFS='&' read -ra pairs <<< "$POST_DATA"
for pair in "${pairs[@]}"; do
  IFS='=' read -r k v <<< "$pair"
  params[$(urldecode "$k")]=$(urldecode "$v")
done

hostname="${params[hostname]}"
ip="${params[ip]}"
port="${params[port]}"
protocol="${params[protocol]}"
service="${params[service]}"
flag="${params[flag]}"
timestamp=$(date -Iseconds)

score=0
correct=0

# Check mapping.txt for matching line
mapping=$(grep -i "^$service:" /etc/mapping.txt)

if [[ -n "$mapping" ]]; then
  [[ "$mapping" == *"Hostname=$hostname"* ]] && ((score++, correct++))
  [[ "$mapping" == *"IP=$ip"* ]] && ((score++, correct++))
  [[ "$mapping" == *"Port=$port"* ]] && ((score++, correct++))
  [[ "$mapping" == *"Proto=$protocol"* ]] && ((score++, correct++))
  [[ "$mapping" == *"Flag=$flag"* ]] && ((score++, correct++))
  ((score++))  # Assume service match is correct by default

  [[ $correct -eq 6 ]] && ((score+=5))
else
  ((score--))
fi

# Write to /etc/score_card if at least one correct
if [[ $score -gt 0 ]]; then
  echo "hostname=$hostname service=$service target=$ip port=$port proto=$protocol flag=$flag" >> /etc/score_card
fi

# Append to /etc/score.json using jq (fallback to raw append if jq not available)
score_json="/etc/score.json"

if command -v jq &>/dev/null; then
  tmp=$(mktemp)
  jq --arg hn "$hostname" --arg ip "$ip" --arg port "$port" \
     --arg proto "$protocol" --arg service "$service" --arg flag "$flag" \
     --arg ts "$timestamp" --argjson sc "$score" \
     '.entries += [{"host": $hn, "ip": $ip, "port": $port, "protocol": $proto, "service": $service, "flag": $flag, "timestamp": $ts, "score": $sc}]' \
     "$score_json" > "$tmp" && mv "$tmp" "$score_json"
else
  echo "{\"host\":\"$hostname\",\"ip\":\"$ip\",\"port\":\"$port\",\"protocol\":\"$protocol\",\"service\":\"$service\",\"flag\":\"$flag\",\"timestamp\":\"$timestamp\",\"score\":$score}" >> "$score_json"
fi

# Respond with redirect to scorecard page
cat <<EOF
<html>
  <head>
    <meta http-equiv="refresh" content="1;url=/scorecard.html">
  </head>
  <body>
    <p>Score submitted: $score</p>
  </body>
</html>
EOF
