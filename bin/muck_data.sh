#!/usr/bin/env bash
# muck_data.sh
# Usage:
#   Encrypt: ./muck_data.sh "plaintext" "key"
#   Decrypt: ./muck_data.sh -d "hexcipher" "key"

decrypt=false
if [[ $1 == "-d" ]]; then
  decrypt=true
  shift
fi

input="$1"
key="$2"

# Build an array of key-bytes
read -r -a K < <(echo -n "$key" | od -An -tx1)
keylen=${#K[@]}

if $decrypt; then
  hexstr="$input"
  out=""
  # Process each pair of hex digits
  for ((i=0; i<${#hexstr}; i+=2)); do
    hexbyte=${hexstr:i:2}
    p=$((16#$hexbyte))
    k=$((16#${K[$((i/2 % keylen))]}))
    x=$((p ^ k))
    # accumulate as \xHH escapes
    out+="\\x$(printf '%02x' $x)"
  done
  # Print as raw bytes
  printf '%b' "$out"
else
  # Encrypt mode: read plaintext bytes
  read -r -a P < <(echo -n "$input" | od -An -tx1)
  out=""
  for i in "${!P[@]}"; do
    p=$((16#${P[i]}))
    k=$((16#${K[$((i % keylen))]}))
    x=$((p ^ k))
    # accumulate ciphertext hex
    out+="$(printf '%02x' $x)"
  done
  echo "$out"
fi
