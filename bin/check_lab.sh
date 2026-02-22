#!/usr/bin/env bash
set -euo pipefail

APP="NFR-CheckLab"
VERSION="2.2.9"
USER_NAME="Lee 'MadHat' Heath <lheath@unspecific.com>"
NAME_OVERRIDE=false

# Auto-detect installation directory (parent of this script's directory)
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
INSTALL_DIR="$(dirname "$(dirname "$SCRIPT_PATH")")"

show_help() {
    cat << EOF

$APP v$VERSION by Lee 'MadHat' Heath <lheath@unspecific.com>

Scores a completed lab session by comparing your score_card submissions
against the session's ground truth (mapping.txt).  Prints a breakdown of
correct/incorrect answers and lists any services that were not attempted.

Usage: check_lab [OPTIONS] [SCORE_CARD_FILE]

Arguments:
  SCORE_CARD_FILE   Path to the score_card file to score.
                    Defaults to <install_dir>/score_card.

Options:
  --name NAME         Set the player name displayed in the header
                      (written back into the score_card file)
  --help, -h          Show this help message and exit

EOF
}

# Parse options
while [[ $# -gt 0 ]]; do
    case "$1" in
        --name)
            USER_NAME="$2"
            NAME_OVERRIDE=true
            shift 2
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        --*)
            echo "Unknown option: $1"
            show_help
            exit 1
            ;;
        *)
            break
            ;;
    esac
done

# Determine submission file
if [[ $# -eq 0 ]]; then
    SUBMISSION_FILE="$INSTALL_DIR/score_card"
elif [[ $# -eq 1 ]]; then
    SUBMISSION_FILE="$1"
else
    echo " ❌  Too many arguments."
    show_help
    exit 1
fi

# Header display
echo
echo " 🎩  $APP v$VERSION - $USER_NAME"

# Validate submission file
if [[ ! -e "$SUBMISSION_FILE" ]]; then
    echo " ❌  ScoreCard file not found: $SUBMISSION_FILE"
    echo
    show_help
    exit 1
fi

# Extract session ID and optional name from score_card
SESSION_ID=$(grep -m 1 '^session=' "$SUBMISSION_FILE" | cut -d'=' -f2)
if [[ -z "$SESSION_ID" ]]; then
    echo " ❌  No session ID found in submission file."
    exit 1
fi
SAVED_NAME=$(grep -m 1 '^# Name:' "$SUBMISSION_FILE" | cut -d':' -f2- | xargs)

# Prepend name/session header to score_card when overridden
if [[ "$NAME_OVERRIDE" == true ]]; then
    TMPFILE=$(mktemp)
    {
        echo "# Name: $USER_NAME"
        echo "# Session: $SESSION_ID"
        echo
        cat "$SUBMISSION_FILE"
    } > "$TMPFILE" && mv "$TMPFILE" "$SUBMISSION_FILE"
    echo "ℹ️  Updated $SUBMISSION_FILE with name and session header"
    SAVED_NAME="$USER_NAME"
fi

# Set paths for ground truth
LOG_DIR="logs"
SESSION_DIR="$INSTALL_DIR/$LOG_DIR/lab_$SESSION_ID"
GROUND_TRUTH="$SESSION_DIR/mapping.txt"
if [[ ! -f "$GROUND_TRUTH" ]]; then
    echo " ❌  Ground truth file not found: $GROUND_TRUTH"
    exit 1
fi

echo " ✅  SESSION_ID: $SESSION_ID - Scoring session started"
echo "---------------------------"

# Load ground truth into associative array
declare -A truth_map
while IFS= read -r line; do
    svc="${line%%:*}"
    hostname=$(grep -oP 'Hostname=\K\S+' <<< "$line")
    ip=$(grep -oP 'IP=\K\S+' <<< "$line")
    port=$(grep -oP 'Port=\K\S+' <<< "$line")
    proto=$(grep -oP 'Proto=\K\S+' <<< "$line")
    flag=$(grep -oP 'Flag=\K\S+' <<< "$line")
    key="${hostname}_${svc}_${ip}_${port}_${proto}"
    truth_map["$key"]="$flag"
done < "$GROUND_TRUTH"

# Score the submission
score=0; correct=0; wrong=0; target_count=0
while IFS= read -r line; do
    [[ -z "$line" || "$line" =~ ^# ]] && continue
    [[ "$line" == session=* ]] && continue
    (( target_count++ )) || :
    hostname=$(grep -oP 'hostname=\K\S+' <<< "$line")
    service=$(grep -oP 'service=\K\S+' <<< "$line")
    ip=$(grep -oP 'target=\K\S+' <<< "$line")
    port=$(grep -oP 'port=\K\S+' <<< "$line")
    proto=$(grep -oP 'proto=\K\S+' <<< "$line")
    flag=$(grep -oP 'flag=\K\S+' <<< "$line")
    echo "✅ Checking ${hostname:-entry #$target_count}"
    key="${hostname}_${service}_${ip}_${port}_${proto}"
    correct_flag="${truth_map[$key]}"
    if [[ "$flag" == "$correct_flag" ]]; then
        (( correct++ )) || :; (( score++ )) || :
    else
        (( wrong++ )) || :; (( score-- )) || :
    fi
done < "$SUBMISSION_FILE"

echo "---------------------------"
# Print saved name if present
if [[ -n "$SAVED_NAME" ]]; then
    echo "👤 Name: $SAVED_NAME"
fi
echo " 🧮  Score: $score"
echo " ✔️  Correct: $correct"
echo " ❌  Incorrect: $wrong"

# Identify missed services
declare -A submitted_services
while IFS= read -r line; do
    [[ -z "$line" || "$line" =~ ^# || "$line" == session=* ]] && continue
    hostname=$(grep -oP 'hostname=\K\S+' <<< "$line")
    ip=$(grep -oP 'target=\K\S+' <<< "$line")
    port=$(grep -oP 'port=\K\S+' <<< "$line")
    proto=$(grep -oP 'proto=\K\S+' <<< "$line")
    key="${hostname}_${ip}_${port}_${proto}"
    submitted_services["$key"]=1
done < "$SUBMISSION_FILE"

echo "🕵️  Missed services:"
missed_any=0
for k in "${!truth_map[@]}"; do
    hostname="${k%%_*}"
    ip="$(cut -d'_' -f3 <<< "$k")"
    port="$(cut -d'_' -f4 <<< "$k")"
    proto="$(cut -d'_' -f5 <<< "$k")"
    lookup_key="${hostname}_${ip}_${port}_${proto}"
    if [[ -z "${submitted_services[$lookup_key]}" ]]; then
        echo "- ❗ $hostname ($ip:$port:$proto) was not reported"
        (( missed_any++ )) || :
    fi
done

[[ $missed_any -eq 0 ]] && echo "- 🎯 All services were attempted!"
echo
exit 0
