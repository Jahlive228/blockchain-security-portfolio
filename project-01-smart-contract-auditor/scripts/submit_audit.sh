#!/bin/bash
# Usage: ./scripts/submit_audit.sh contracts/VulnerableBank.sol

CONTRACT=${1:-"contracts/VulnerableBank.sol"}
N8N_URL="http://127.0.0.1:5678/webhook/audit-contract"

echo "[*] Submitting audit for: $CONTRACT"

RESPONSE=$(curl -s -X POST "$N8N_URL" \
  -H "Content-Type: application/json" \
  -d "{\"contract\": \"$CONTRACT\"}")

NEEDS_ALERT=$(echo $RESPONSE | python -c "import sys,json; d=json.load(sys.stdin); print(d.get('needs_alert', False))")
CRITICAL=$(echo $RESPONSE   | python -c "import sys,json; d=json.load(sys.stdin); print(d.get('summary',{}).get('CRITICAL',0))")
HIGH=$(echo $RESPONSE       | python -c "import sys,json; d=json.load(sys.stdin); print(d.get('summary',{}).get('HIGH',0))")
TOTAL=$(echo $RESPONSE      | python -c "import sys,json; d=json.load(sys.stdin); print(d.get('total',0))")

echo ""
echo "Results for: $CONTRACT"
echo "  Total findings : $TOTAL"
echo "  Critical       : $CRITICAL"
echo "  High           : $HIGH"
echo "  Needs alert    : $NEEDS_ALERT"

if [ "$NEEDS_ALERT" = "True" ]; then
  echo ""
  echo "  *** ALERT SENT TO DISCORD ***"
  exit 1
else
  echo ""
  echo "  Contract is CLEAN"
  exit 0
fi