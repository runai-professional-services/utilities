#!/bin/bash
set -euo pipefail

if [ $# -ne 1 ]; then
  echo "Usage: $0 <ngc_api_key>"
  echo "Example: $0 nvapi-xxxxx"
  exit 1
fi

NGC_API_KEY="$1"

echo "=== NGC API Key Validation ==="
echo ""

echo "[1/3] Validating API key..."
ORGS_RESPONSE=$(curl -s -w "\n%{http_code}" \
  -H "Authorization: Bearer $NGC_API_KEY" \
  "https://api.ngc.nvidia.com/v2/orgs")

HTTP_CODE=$(echo "$ORGS_RESPONSE" | tail -1)
BODY=$(echo "$ORGS_RESPONSE" | sed '$d')

if [ "$HTTP_CODE" != "200" ]; then
  echo ""
  echo "FAIL: API key is invalid (HTTP $HTTP_CODE)"
  exit 1
fi

ORG_INFO=$(echo "$BODY" | python3 -c "
import sys, json
d = json.load(sys.stdin)
orgs = d.get('organizations', [])
if not orgs:
    print('NO_ORGS')
else:
    org = orgs[0]
    print(f'ORG_NAME={org[\"name\"]}')
    print(f'ORG_DISPLAY={org[\"displayName\"]}')
" 2>/dev/null)

if echo "$ORG_INFO" | grep -q "NO_ORGS"; then
  echo ""
  echo "FAIL: API key is valid but not associated with any NGC org."
  exit 1
fi

ORG_NAME=$(echo "$ORG_INFO" | grep ORG_NAME | cut -d= -f2)
ORG_DISPLAY=$(echo "$ORG_INFO" | grep ORG_DISPLAY | cut -d= -f2)
echo "[1/3] Done. Key belongs to org: $ORG_DISPLAY ($ORG_NAME)"

echo "[2/3] Checking NIM product enablements..."
NIM_PRODUCTS=$(echo "$BODY" | python3 -c "
import sys, json
d = json.load(sys.stdin)
nim_keywords = ['NIM', 'NVAIE']
for org in d.get('organizations', []):
    for p in org.get('productEnablements', []):
        name = p.get('productName', '')
        if any(k in name for k in nim_keywords):
            exp = p.get('expirationDate', 'no expiry')
            print(f'  {p[\"type\"]}: {name} (expires: {exp})')
" 2>/dev/null)

if [ -z "$NIM_PRODUCTS" ]; then
  echo ""
  echo "FAIL: Org ($ORG_DISPLAY) has no NIM/NVAIE product enablements."
  echo "  NIM images require an NVIDIA AI Enterprise license or NIM evaluation."
  exit 1
fi

echo "[2/3] Done. NIM-related enablements:"
echo "$NIM_PRODUCTS"
echo ""

echo "[3/3] Checking registry authentication..."
TOKEN_RESPONSE=$(curl -s -u '$oauthtoken':"$NGC_API_KEY" \
  "https://authn.nvidia.com/token?service=registry")

HAS_TOKEN=$(echo "$TOKEN_RESPONSE" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print('yes' if d.get('token') else 'no')
except:
    print('no')
" 2>/dev/null)

if [ "$HAS_TOKEN" = "no" ]; then
  echo ""
  echo "FAIL: Could not obtain a registry token."
  exit 1
fi
echo "[3/3] Done. Registry token obtained."

echo ""
echo "PASS: NGC API key is valid and has NIM pull access"
echo "  Org: $ORG_DISPLAY ($ORG_NAME)"
