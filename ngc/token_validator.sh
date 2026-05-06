#!/bin/bash
set -euo pipefail

if [ $# -ne 2 ]; then
  echo "Usage: $0 <image> <ngc_api_key>"
  echo "Example: $0 nvcr.io/nvidia/cuda:12.8.0-base-ubuntu22.04 nvapi-xxxxx"
  exit 1
fi

IMAGE="$1"
NGC_API_KEY="$2"
REPO_PATH=$(echo "$IMAGE" | sed 's|nvcr.io/||' | sed 's|:.*||')

echo "=== NGC API Key Validation ==="
echo "Image: $IMAGE"
echo "Repository: $REPO_PATH"
echo ""

echo "[1/4] Requesting auth challenge from registry..."
AUTH_HEADER=$(curl -s -I -u '$oauthtoken':"$NGC_API_KEY" \
  "https://nvcr.io/v2/${REPO_PATH}/tags/list" 2>&1 \
  | grep -i www-authenticate)

if [ -z "$AUTH_HEADER" ]; then
  echo "[1/4] No auth challenge received, trying direct auth..."
  HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
    -u '$oauthtoken':"$NGC_API_KEY" \
    "https://nvcr.io/v2/${REPO_PATH}/tags/list")
  if [ "$HTTP_CODE" -eq 200 ]; then
    echo ""
    echo "PASS: NGC API key is valid and has pull access to $IMAGE"
    exit 0
  else
    echo ""
    echo "FAIL: NGC API key cannot access $IMAGE (HTTP $HTTP_CODE)"
    exit 1
  fi
fi
echo "[1/4] Done."

echo "[2/4] Parsing token service endpoint..."
REALM=$(echo "$AUTH_HEADER" | sed 's/.*realm="\([^"]*\)".*/\1/')
SERVICE=$(echo "$AUTH_HEADER" | sed 's/.*service="\([^"]*\)".*/\1/')
SCOPE=$(echo "$AUTH_HEADER" | sed 's/.*scope="\([^"]*\)".*/\1/')
echo "[2/4] Done."

echo "[3/4] Exchanging API key for bearer token..."
TOKEN_RESPONSE=$(curl -s -u '$oauthtoken':"$NGC_API_KEY" \
  "${REALM}?service=${SERVICE}&scope=${SCOPE}")

TOKEN=$(echo "$TOKEN_RESPONSE" | grep -o '"token":"[^"]*"' | head -1 | cut -d'"' -f4)

if [ -z "$TOKEN" ]; then
  echo ""
  echo "FAIL: Could not obtain bearer token. The API key may be invalid."
  echo "Token service response: $TOKEN_RESPONSE"
  exit 1
fi
echo "[3/4] Done."

echo "[4/4] Verifying pull access to repository..."
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
  -H "Authorization: Bearer $TOKEN" \
  "https://nvcr.io/v2/${REPO_PATH}/tags/list")
echo "[4/4] Done."

echo ""
if [ "$HTTP_CODE" -eq 200 ]; then
  echo "PASS: NGC API key is valid and has pull access to $IMAGE"
else
  echo "FAIL: NGC API key cannot pull $IMAGE (HTTP $HTTP_CODE)"
  exit 1
fi
