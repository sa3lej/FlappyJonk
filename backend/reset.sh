#!/bin/sh
# Nollar världslistan — eller tar bort ETT namn: ./reset.sh TROLLNAMN
# Kräver .admin_key i samma mapp (finns bara på Lars-Eriks dator).
DIR="$(dirname "$0")"
URL="https://flappyjonk.jonsson-es.workers.dev"
KEY="$(cat "$DIR/.admin_key")"
if [ -n "$1" ]; then
  curl -s -X POST "$URL/remove" -H "X-Admin-Key: $KEY" -H "Content-Type: application/json" -d "{\"name\":\"$1\"}"
else
  curl -s -X POST "$URL/reset" -H "X-Admin-Key: $KEY"
fi
echo ""
