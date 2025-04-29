#!/bin/bash

# Paths
SCORECARD="/etc/score_card"
MAPPING="/etc/mapping.txt"
SCOREJSON="/etc/score.json"


# Helpers
urldecode() { local data=${1//+/ }; printf '%b' "${data//%/\\x}"; }
read_post_data() { read -n "${CONTENT_LENGTH}" POST_DATA; }
parse_form() {
    echo "$POST_DATA" | tr '&' '\n' | while IFS='=' read -r key value; do
        key=$(urldecode "$key")
        value=$(urldecode "$value")
        eval "${key}=\"${value}\""
    done
}

load_score() {
    if [ -f "$SCOREJSON" ]; then
        score=$(sed -n 's/.*"score": *\([0-9-]*\).*/\1/p' "$SCOREJSON")
    else
        score=0
    fi
}

http_headers() {
    echo "Content-Type: text/html"
    echo ""
}

load_scorecard() {
    echo "<table border='1' cellpadding='5' cellspacing='0'>"
    echo "<tr><th>Service</th><th>Host</th><th>IP</th><th>Port</th><th>Protocol</th><th>Flag</th></tr>"

    while IFS= read -r line; do
        case "$line" in \#*) continue ;; esac
        service=$(echo "$line" | sed -n 's/.*service=\([^ ]*\).*/\1/p')
        target=$(echo "$line" | sed -n 's/.*target=\([^ ]*\).*/\1/p')
        port=$(echo "$line" | sed -n 's/.*port=\([^ ]*\).*/\1/p')
        proto=$(echo "$line" | sed -n 's/.*proto=\([^ ]*\).*/\1/p')
        flag=$(echo "$line" | sed -n 's/.*flag=\([^ ]*\).*/\1/p')
        hostname=$(echo "$line" | sed -n 's/.*hostname=\([^ ]*\).*/\1/p')
        readonly_flag=""
        echo "$line" | grep -q 'readonly=true' && readonly_flag="readonly"

        echo "<tr>"
        echo "<td><input type='text' name='service_$port' value='$service' $readonly_flag></td>"
        echo "<td><input type='text' name='host_$port' value='$hostname' $readonly_flag></td>"
        echo "<td><input type='text' name='ip_$port' value='$target' $readonly_flag></td>"
        echo "<td><input type='text' name='port_$port' value='$port' readonly></td>"
        echo "<td><input type='text' name='proto_$port' value='$proto' $readonly_flag></td>"
        echo "<td><input type='text' name='flag_$port' value='$flag' $readonly_flag></td>"
        echo "</tr>"
    done < "$SCORECARD"

    echo "</table>"
}

submit_answers() {
    temp_scorecard="/tmp/score_card.$$"
    temp_scorejson="/tmp/score.json.$$"
    total=0
    correct=0
    wrong=0
    bonus=0

    while IFS= read -r line; do
        key=$(echo "$line" | sed -n 's/.*Port=\([^ ]*\).*/\1/p')_$(echo "$line" | sed -n 's/.*Proto=\([^ ]*\).*/\1/p')
        mapping_service["$key"]=$(echo "$line" | cut -d':' -f1)
        mapping_host["$key"]=$(echo "$line" | sed -n 's/.*Hostname=\([^ ]*\).*/\1/p')
        mapping_ip["$key"]=$(echo "$line" | sed -n 's/.*IP=\([^ ]*\).*/\1/p')
        mapping_proto["$key"]=$(echo "$line" | sed -n 's/.*Proto=\([^ ]*\).*/\1/p')
        mapping_flag["$key"]=$(echo "$line" | sed -n 's/.*Flag=\([^ ]*\).*/\1/p')
    done < "$MAPPING"

    {
    grep '^#' "$SCORECARD"
    echo "session=${SESSION_ID}"

    while IFS= read -r line; do
        case "$line" in \#*) continue ;; esac
        port=$(echo "$line" | sed -n 's/.*port=\([^ ]*\).*/\1/p')
        proto=$(echo "$line" | sed -n 's/.*proto=\([^ ]*\).*/\1/p')
        key="${port}_${proto}"

        eval submitted_service="\${service_${port}}"
        eval submitted_host="\${host_${port}}"
        eval submitted_ip="\${ip_${port}}"
        eval submitted_proto="\${proto_${port}}"
        eval submitted_flag="\${flag_${port}}"

        total=$((total+1))

        if [ "$submitted_service" = "${mapping_service[$key]}" ] &&
           [ "$submitted_host" = "${mapping_host[$key]}" ] &&
           [ "$submitted_ip" = "${mapping_ip[$key]}" ] &&
           [ "$submitted_proto" = "${mapping_proto[$key]}" ] &&
           [ "$submitted_flag" = "${mapping_flag[$key]}" ]; then
            correct=$((correct+1))
            echo "hostname=$submitted_host service=$submitted_service target=$submitted_ip port=$port proto=$submitted_proto flag=$submitted_flag readonly=true"
        else
            wrong=$((wrong+1))
            echo "hostname=$submitted_host service=$submitted_service target=$submitted_ip port=$port proto=$submitted_proto flag=$submitted_flag"
        fi
    done < "$SCORECARD"
    } > "$temp_scorecard"

    [ "$wrong" -eq 0 ] && [ "$total" -gt 0 ] && bonus=5
    score=$((correct - wrong + bonus))

    mv "$temp_scorecard" "$SCORECARD"

    {
    echo "{"
    echo "\"correct\": $correct,"
    echo "\"wrong\": $wrong,"
    echo "\"bonus\": $bonus,"
    echo "\"score\": $score"
    echo "}"
    } > "$temp_scorejson"
    mv "$temp_scorejson" "$SCOREJSON"
}

edit_user() {
    [ -n "$username" ] && sed -i "/^#.*$/a# User=$username" "$SCORECARD"
}

reset_scorecard() {
    grep '^#' "$SCORECARD" > "${SCORECARD}.tmp"
    echo "session=${SESSION_ID}" >> "${SCORECARD}.tmp"
    mv "${SCORECARD}.tmp" "$SCORECARD"
    echo "{}" > "$SCOREJSON"
}

logger $(env)

load_score

# Main execution
http_headers

if [ "$REQUEST_METHOD" = "POST" ]; then
    read_post_data
    parse_form
    case "$action" in
        submit) submit_answers ;;
        edit_user) edit_user ;;
        reset) reset_scorecard ;;
    esac
fi

# Page output
echo "<html><head><title>Nmap Firing Range Score Card</title>"
echo "<style>
body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; background:#f0f2f5; margin:0; padding:20px; }
h1 { text-align:center; }
table { width:100%; border-collapse:collapse; margin:20px auto; }
table, th, td { border:1px solid #ccc; }
th { background:#007BFF; color:white; padding:10px; }
td { padding:8px; text-align:center; }
tr:nth-child(even) { background:#f9f9f9; }
input[type=text] { width:95%; padding:6px; border:1px solid #aaa; border-radius:4px; }
input[type=submit], button { background:#28a745; color:white; padding:10px 20px; margin:10px; border:none; border-radius:6px; cursor:pointer; font-size:1em; }
input[type=submit]:hover, button:hover { background:#218838; }
</style></head><body>"

echo "<h1>Nmap Firing Range &nbsp;&nbsp; Score Card</h1>"
echo "<form method='POST' action='/cgi-bin/score_card.cgi'>"

load_scorecard

echo "<input type='hidden' name='action' value='submit'>"
echo "<input type='submit' value='Submit'>"
echo "</form>"

cat <<EOF
<button onclick='editUser()'>Edit Username</button>
<button onclick='resetCard()'>Reset Scorecard</button>
<script>
function editUser() {
    var name = prompt("Enter new username:");
    if (name != null) {
        var form = document.createElement('form');
        form.method = "POST";
        form.action = "/cgi-bin/score_card.cgi";
        form.innerHTML = "<input type='hidden' name='action' value='edit_user'>" +
                         "<input type='hidden' name='username' value='" + name + "'>";
        document.body.appendChild(form);
        form.submit();
    }
}
function resetCard() {
    if (confirm("Reset the scorecard?")) {
        var form = document.createElement('form');
        form.method = "POST";
        form.action = "/cgi-bin/score_card.cgi";
        form.innerHTML = "<input type='hidden' name='action' value='reset'>";
        document.body.appendChild(form);
        form.submit();
    }
}
</script>
</body></html>
EOF

exit 0
