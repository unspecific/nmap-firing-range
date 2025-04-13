#!/bin/bash


APP="NFR-CheckLab"
VERSION=0.5

echo
echo " 🎩  $APP v$VERSION - Lee 'MadHat' Heath <lheath@unspecific.com>"


# -- Validate input file --
if [[ $# -ne 1 ]]; then
  echo
  echo "This is the script to score your Nmap Firing Range session"
  echo "The submission_file should be in the following format"
  echo
  echo "session=123abc"
  echo "service=http target=192.168.200.42 port=8080 proto=tcp flag=FLAG{abc123}"
  echo "service=ftp target=192.168.200.99 port=21 proto=tcp flag=FLAG{wrongflag}"
  echo "service=telnet target=192.168.200.77 port=9999 proto=tcp flag=FLAG{abc999}"
  echo
  echo "Usage: $0 <submission_file>"
  echo
  exit 1
fi

SUBMISSION_FILE="$1"

if [[ ! -f "$SUBMISSION_FILE" ]]; then
  echo "❌ Submission file not found: $SUBMISSION_FILE"
  exit 1
fi

# -- Extract session ID from submission file --
SESSION_ID=$(grep -m 1 '^session=' "$SUBMISSION_FILE" | cut -d'=' -f2)

if [[ -z "$SESSION_ID" ]]; then
  echo "❌ No session ID found in submission file."
  exit 1
fi

# -- Set path to ground-truth file based on session --
LAB_DIR="/opt/firing-range"
LOG_DIR="logs"
SESSION_DIR="$LAB_DIR/$LOG_DIR/lab_$SESSION_ID"
GROUND_TRUTH="$SESSION_DIR/mapping.txt"

if [[ ! -f "$GROUND_TRUTH" ]]; then
  echo "❌ Ground truth file not found: $GROUND_TRUTH"
  exit 1
fi
echo "✅ SESSION_ID: $SESSION_ID - Scoring session started"
echo "---------------------------"

# -- Load ground truth into associative array --
declare -A truth_map

while read -r line; do
  svc=$(echo "$line" | cut -d':' -f1)
  ip=$(echo "$line" | grep -oP 'IP=\K\S+')
  port=$(echo "$line" | grep -oP 'Port=\K\S+')
  proto=$(echo "$line" | grep -oP 'Proto=\K\S+')
  flag=$(echo "$line" | grep -oP 'Flag=\K\S+')
  key="${svc}_${ip}_${port}_${proto}"
  truth_map["$key"]="$flag"
done < "$GROUND_TRUTH"

# declare -p truth_map

# -- Score the submission file --
score=0
correct=0
wrong=0

while read -r line; do
  # Skip blank or comment lines
  [[ -z "$line" || "$line" =~ ^# ]] && continue

  if [[ "$line" == session=* ]]; then
    # echo "📘 $line"
    continue
  fi

  service=$(echo "$line" | grep -oP 'service=\K\S+')
  proto=$(echo "$line" | grep -oP 'proto=\K\S+')
  ip=$(echo "$line" | grep -oP 'target=\K\S+')
  port=$(echo "$line" | grep -oP 'port=\K\S+')
  flag=$(echo "$line" | grep -oP 'flag=\K\S+')

  key="${service}_${ip}_${port}_${proto}"
  correct_flag="${truth_map[$key]}"

  if [[ "$flag" == "$correct_flag" ]]; then
    echo "✅ $service $ip:$port:$proto → Flag Match +5 pts"
    ((score+=5))
    ((correct++))
  else
    echo "❌ $service $ip:$port:$proto → No Flag Match -1 pts"
    ((score-=1))
    ((wrong++))
  fi
# Try fallback: search all keys for matching IP, port, and flag
  for k in "${!truth_map[@]}"; do
    svc_service=$(cut -d'_' -f1 <<< "$k")
    svc_ip=$(cut -d'_' -f2 <<< "$k")
    svc_port=$(cut -d'_' -f3 <<< "$k")
    svc_proto=$(cut -d'_' -f4 <<< "$k")
    svc_flag="${truth_map[$k]}"

    if [[ "$ip" == "$svc_ip" && "$port" == "$svc_port" && "$proto" == "$svc_proto" && "$flag" == "$svc_flag" && "$service" != "$svc_service" ]]; then
      echo "✅ $service $ip:$port:$proto → Network correct (misidentified service) +4 pts"
      ((score+=4))
      ((correct+=4))
      ((wrong++))
      break
    fi
    if [[ "$ip" == "$svc_ip" && "$port" == "$svc_port" && "$proto" == "$svc_proto" ]]; then
      echo "✅ $service $ip:$port:$proto → Network Identified (IP, Port and Protocol are correct) +3 pts"
      ((score+=3))
      ((correct+=3))
      ((wrong+=2))
      break
    fi
    if [[ "$ip" == "$svc_ip" && "$port" == "$svc_port" ]]; then
      echo "✅ $service $ip:$port:$proto → Minimal Network Identified (IP, Port are correct) +1 pts"
      ((score+=1))
      ((correct++))
      ((wrong+=4))
      break
    fi
  done

 
done < "$SUBMISSION_FILE"

# -- Final score summary --
echo "---------------------------"
echo "🧮 Score: $score"
echo "✔️  Correct: $correct"
echo "❌ Incorrect: $wrong"

# -- Identify missed services (not reported by user) --
declare -A submitted_services

# Re-read the submission file to track what they attempted
while read -r line; do
  [[ -z "$line" || "$line" =~ ^# || "$line" == session=* ]] && continue

  ip=$(echo "$line" | grep -oP 'target=\K\S+')
  port=$(echo "$line" | grep -oP 'port=\K\S+')
  proto=$(echo "$line" | grep -oP 'proto=\K\S+')
  service=$(echo "$line" | grep -oP 'service=\K\S+')

  key="${ip}_${port}_${proto}"
  submitted_services["$key"]=1
done < "$SUBMISSION_FILE"

# Check against ground truth
echo "🕵️  Missed services:"
missed_any=0
for k in "${!truth_map[@]}"; do
  ip=$(cut -d'_' -f2 <<< "$k")
  port=$(cut -d'_' -f3 <<< "$k")
  proto=$(cut -d'_' -f4 <<< "$k")
  lookup_key="${ip}_${port}_${proto}"

  if [[ -z "${submitted_services[$lookup_key]}" ]]; then
    echo "- ❗ $ip:$port:$proto was not reported"
    missed_any=1
  fi
done

if [[ "$missed_any" -eq 0 ]]; then
  echo "- 🎯 All services were attempted!"
fi
echo
exit