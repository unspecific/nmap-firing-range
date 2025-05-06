#!/bin/bash

echo "Content-Type: text/plain"
echo ""

docker ps --format "→ {{.Names}} | {{.Status}} | {{.Ports}}"
