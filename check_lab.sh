#!/bin/bash


APP="NFR-CheckLab"
VERSION=2.0

echo
echo " 🎩  $APP v$VERSION - Lee 'MadHat' Heath <lheath@unspecific.com>"


# -- Validate input file --
if [[ $# -ne 1 ]]; then
  SUBMISSION_FILE="score_card"
else
  SUBMISSION_FILE="$1"
fi


if [[ ! -f "$SUBMISSION_FILE" ]]; then
  echo "❌ ScoreCard file not found: $SUBMISSION_FILE"
  echo 
  echo "Usage: check_lab <SCORE_CARD>"
  echo " <SCORE_CARD> is generated in the \$PWD when launch_lab is run."
  echo " The score_card format can be seen on GitHub. The score_card includes"
  echo " a SESSION_ID, and your submissions for the targets you have found."
  echo " by defaut it looks for './score_card' or you can pass it the name of the scroe card file."
  echo
  echo "   Please specify the score_card file you wish to use if there is not './score_card'."
  exit 1;
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
  hostname=$(echo "$line" | grep -oP 'Hostname=\K\S+')
  ip=$(echo "$line" | grep -oP 'IP=\K\S+')
  port=$(echo "$line" | grep -oP 'Port=\K\S+')
  proto=$(echo "$line" | grep -oP 'Proto=\K\S+')
  flag=$(echo "$line" | grep -oP 'Flag=\K\S+')
  key="${hostname}_${svc}_${ip}_${port}_${proto}"
  truth_map["$key"]="$flag"
done < "$GROUND_TRUTH"

# declare -p truth_map

# -- Score the submission file --
score=0
correct=0
wrong=0
target_count=0

while read -r line; do
  # Skip blank or comment lines
  [[ -z "$line" || "$line" =~ ^# ]] && continue
  # We don't need the session ID here
  if [[ "$line" == session=* ]]; then
    # echo "📘 $line"
    continue
  fi

  # 
  ((target_count++))

  hostname=$(echo "$line" | grep -oP 'hostname=\K\S+')
  service=$(echo "$line" | grep -oP 'service=\K\S+')
  proto=$(echo "$line" | grep -oP 'proto=\K\S+')
  ip=$(echo "$line" | grep -oP 'target=\K\S+')
  port=$(echo "$line" | grep -oP 'port=\K\S+')
  flag=$(echo "$line" | grep -oP 'flag=\K\S+')
  if [[ -z "$hostnmae" ]]; then
    echo "✅ Checking entry #${target_count}"
  else
    echo "✅ Checking $hostname"
  fi
  if [[ !$hostname && !$service && !$flag && !$proto && !$ip && !$port ]]; then
    echo " ❗ Empty entry"
    continue
  fi
  key="${hostname}_${service}_${ip}_${port}_${proto}"
  correct_flag="${truth_map[$key]}"

  for k in "${!truth_map[@]}"; do
    svc_hostname=$(cut -d'_' -f1 <<< "$k")
    svc_service=$(cut -d'_' -f2 <<< "$k")
    svc_ip=$(cut -d'_' -f3 <<< "$k")
    svc_port=$(cut -d'_' -f4 <<< "$k")
    svc_proto=$(cut -d'_' -f5 <<< "$k")
    svc_flag="${truth_map[$k]}"

    for field in hostname ip port service protocol flag; do
      submitted_val="${!field}"        # e.g., $hostname
      correct_val="${!svc_$field}"     # e.g., $svc_hostname

      if [[ -z "$submitted_val" ]]; then
        continue  # skip blank entries
      elif [[ "$submitted_val" == "$correct_val" ]]; then
        ((correct++))
        ((score++))
      else
        ((wrong++))
        ((score--))
      fi
    done

   if [[ "$hostname" == "$svc_hostname" && "$ip" == "$svc_ip" && "$port" == "$svc_port" && "$proto" == "$svc_proto" && "$flag" == "$svc_flag" && "$service" != "$svc_service" ]]; then
      echo "✅ $service $ip:$port:$proto → Perfect Entry (+5 bonus points)"
      ((score+=5))
      ((correct+=5))
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

  hostname=$(echo "$line" | grep -oP 'hostname=\K\S+')
  ip=$(echo "$line" | grep -oP 'target=\K\S+')
  port=$(echo "$line" | grep -oP 'port=\K\S+')
  proto=$(echo "$line" | grep -oP 'proto=\K\S+')
  service=$(echo "$line" | grep -oP 'service=\K\S+')

  key="${hostname}_${ip}_${port}_${proto}"
  submitted_services["$key"]=1
done < "$SUBMISSION_FILE"

# Check against ground truth
echo "🕵️  Missed services:"
missed_any=0
for k in "${!truth_map[@]}"; do
  hostname=$(cut -d'_' -f1 <<< "$k")
  ip=$(cut -d'_' -f3 <<< "$k")
  port=$(cut -d'_' -f4 <<< "$k")
  proto=$(cut -d'_' -f5 <<< "$k")
  lookup_key="${hostname}_${ip}_${port}_${proto}"

  if [[ -z "${submitted_services[$lookup_key]}" ]]; then
    echo "- ❗ $hostname ($ip:$port:$proto) was not reported"
    missed_any=1
  fi
done

if [[ "$missed_any" -eq 0 ]]; then
  echo "- 🎯 All services were attempted!"
fi
echo
exit