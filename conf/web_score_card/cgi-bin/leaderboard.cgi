#!/bin/bash

echo "Content-type: application/json"
echo "Cache-Control: no-cache"
echo ""

score_json="/etc/score.json"

if [[ ! -f "$score_json" ]]; then
  echo "[]"
  exit 0
fi

# Aggregate score.json by player: sum scores, count submissions, sort desc
jq '[.entries | group_by(.player)[] |
  {player: .[0].player, score: (map(.score) | add), submissions: length}] |
  sort_by(-.score)' "$score_json"
