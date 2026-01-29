#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Print with color
print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_info() {
    echo -e "${YELLOW}ℹ $1${NC}"
}

# Usage function
usage() {
    echo "Usage: $0 --username <USERNAME> --url <CTRL_PLANE_URL> [--password <PASSWORD>]"
    echo ""
    echo "Options:"
    echo "  --username    Username to grant admin permissions (e.g., test@run.ai)"
    echo "  --url         Run:ai control plane URL (e.g., https://runai.example.com)"
    echo "  --password    User's password (optional - will prompt if not provided)"
    echo ""
    echo "Examples:"
    echo "  # Interactive password prompt (recommended for special characters):"
    echo "  $0 --username test@run.ai --url https://runai.example.com"
    echo ""
    echo "  # With password as argument:"
    echo "  $0 --username test@run.ai --url https://runai.example.com --password 'MyPass123!'"
    echo ""
    echo "  # Using environment variable:"
    echo "  export USER_PASSWORD='MyPass123!'"
    echo "  $0 --username test@run.ai --url https://runai.example.com --password \"\$USER_PASSWORD\""
    exit 1
}

# Parse arguments
USERNAME=""
PASSWORD=""
CTRL_PLANE_URL=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --username)
            USERNAME="$2"
            shift 2
            ;;
        --password)
            PASSWORD="$2"
            shift 2
            ;;
        --url)
            CTRL_PLANE_URL="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            print_error "Unknown option: $1"
            usage
            ;;
    esac
done

# Validate required arguments
if [ -z "$USERNAME" ] || [ -z "$CTRL_PLANE_URL" ]; then
    print_error "Username and Control Plane URL are required"
    usage
fi

# Remove trailing slash from URL if present
CTRL_PLANE_URL="${CTRL_PLANE_URL%/}"

# Prompt for password if not provided
if [ -z "$PASSWORD" ]; then
    echo ""
    print_info "Password not provided, prompting for input..."
    read -s -p "Enter password for $USERNAME: " PASSWORD
    echo ""
    if [ -z "$PASSWORD" ]; then
        print_error "Password cannot be empty"
        exit 1
    fi
fi

echo ""
echo "=========================================="
echo "Grant Admin Permission Tool"
echo "=========================================="
echo ""

# Check required tools
if ! command -v curl &> /dev/null; then
    print_error "curl is not installed or not in PATH"
    exit 1
fi

if ! command -v jq &> /dev/null; then
    print_error "jq is not installed or not in PATH"
    exit 1
fi

print_info "Target username: $USERNAME"
print_info "Control Plane URL: $CTRL_PLANE_URL"
echo ""

# Step 1: Get API token
print_info "Step 1: Obtaining Run:ai API token..."

# Properly escape password for JSON
PASSWORD_JSON=$(printf '%s' "$PASSWORD" | jq -Rs .)

TOKEN_RESPONSE=$(curl -s -X POST "$CTRL_PLANE_URL/api/v1/token" \
  -H "Content-Type: application/json" \
  -d "{\"grantType\":\"password\",\"clientID\":\"cli\",\"username\":\"$USERNAME\",\"password\":$PASSWORD_JSON}")

USER_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.accessToken // empty')

if [ -z "$USER_TOKEN" ]; then
    print_error "Failed to obtain API token"
    ERROR_MSG=$(echo "$TOKEN_RESPONSE" | jq -r '.error_description // .error // empty')
    if [ -n "$ERROR_MSG" ]; then
        print_error "Error: $ERROR_MSG"
    fi
    exit 1
fi

print_success "API token obtained"
echo ""

# Step 2: Get System administrator role ID
print_info "Step 2: Finding System administrator role ID..."
ADMIN_ROLE=$(curl -s "$CTRL_PLANE_URL/api/v1/authorization/roles" \
  -H "Authorization: Bearer $USER_TOKEN" 2>&1)

ADMIN_ROLE_ID=$(echo "$ADMIN_ROLE" | jq -r '.[] | select(.name == "System administrator") | .id // empty')

if [ -z "$ADMIN_ROLE_ID" ]; then
    print_error "Failed to find System administrator role"
    exit 1
fi

print_success "System administrator role ID: $ADMIN_ROLE_ID"
echo ""

# Step 3: Get Tenant ID from JWT token
print_info "Step 3: Extracting Tenant ID from JWT token..."

# Extract payload from JWT
PAYLOAD=$(echo "$USER_TOKEN" | cut -d'.' -f2)
# Add padding if needed for base64 decoding
PADDING=$((4 - ${#PAYLOAD} % 4))
if [ $PADDING -ne 4 ]; then
    PAYLOAD="${PAYLOAD}$(printf '%*s' $PADDING | tr ' ' '=')"
fi

TENANT_ID=$(echo "$PAYLOAD" | base64 -d 2>/dev/null | jq -r '.tenant_id // empty')

if [ -z "$TENANT_ID" ] || [ "$TENANT_ID" = "null" ]; then
    print_error "Failed to extract Tenant ID from JWT token"
    exit 1
fi

print_success "Tenant ID: $TENANT_ID"
echo ""

# Step 4: Check existing access rules
print_info "Step 4: Checking existing permissions for $USERNAME..."
ACCESS_RULES=$(curl -s "$CTRL_PLANE_URL/api/v1/authorization/access-rules?subjectId=$USERNAME&scopeType=tenant&scopeId=$TENANT_ID" \
  -H "Authorization: Bearer $USER_TOKEN" 2>&1)

# Check if user already has System administrator role at tenant scope
HAS_ADMIN=$(echo "$ACCESS_RULES" | jq -r --argjson roleId "$ADMIN_ROLE_ID" \
  '.accessRules // [] | map(select(.roleId == $roleId and .scopeType == "tenant")) | length')

if [ "$HAS_ADMIN" -gt 0 ]; then
    print_success "User already has System administrator role at tenant scope - no action needed"
    echo ""
    echo "=========================================="
    print_success "Task completed - user already has admin permissions"
    echo "=========================================="
    exit 0
fi

print_info "User does not have System administrator role at tenant scope"
echo ""

# Step 5: Grant System administrator permission
print_info "Step 5: Granting System administrator permission to $USERNAME..."
GRANT_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$CTRL_PLANE_URL/api/v1/authorization/access-rules" \
  -H "Authorization: Bearer $USER_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"subjectId\": \"$USERNAME\",
    \"subjectType\": \"user\",
    \"roleId\": $ADMIN_ROLE_ID,
    \"scopeId\": \"$TENANT_ID\",
    \"scopeType\": \"tenant\"
  }" 2>&1)

HTTP_CODE=$(echo "$GRANT_RESPONSE" | tail -n1)
RESPONSE_BODY=$(echo "$GRANT_RESPONSE" | sed '$d')

if [ "$HTTP_CODE" != "201" ] && [ "$HTTP_CODE" != "200" ]; then
    print_error "Failed to grant System administrator permission (HTTP $HTTP_CODE)"
    if [ -n "$RESPONSE_BODY" ]; then
        print_error "Response: $RESPONSE_BODY"
    fi
    exit 1
fi

print_success "System administrator permission granted successfully"
echo ""

# Step 6: Verify the permission was added
print_info "Step 6: Verifying permission was added..."
VERIFY_RULES=$(curl -s "$CTRL_PLANE_URL/api/v1/authorization/access-rules?subjectId=$USERNAME&scopeType=tenant&scopeId=$TENANT_ID" \
  -H "Authorization: Bearer $USER_TOKEN" 2>&1)

VERIFY_ADMIN=$(echo "$VERIFY_RULES" | jq -r --argjson roleId "$ADMIN_ROLE_ID" \
  '.accessRules // [] | map(select(.roleId == $roleId and .scopeType == "tenant")) | length')

if [ "$VERIFY_ADMIN" -gt 0 ]; then
    print_success "Verified: System administrator permission is active"
else
    print_error "Warning: Could not verify the permission was added"
fi

echo ""
echo "=========================================="
print_success "System administrator permission granted successfully!"
echo "=========================================="
echo ""
echo "User $USERNAME now has System administrator role at tenant scope."
echo "They can now:"
echo "  - Access all Run:ai features"
echo "  - Manage users and access rules"
echo "  - Configure SSO and security settings"
echo ""
echo "Control Plane URL: $CTRL_PLANE_URL"
