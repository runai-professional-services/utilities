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

TOKEN_RESPONSE_FULL=$(curl -s -w "\n%{http_code}" -X POST "$CTRL_PLANE_URL/api/v1/token" \
  -H "Content-Type: application/json" \
  -d "{\"grantType\":\"password\",\"clientID\":\"cli\",\"username\":\"$USERNAME\",\"password\":$PASSWORD_JSON}" 2>&1)

HTTP_CODE=$(echo "$TOKEN_RESPONSE_FULL" | tail -n1)
TOKEN_RESPONSE=$(echo "$TOKEN_RESPONSE_FULL" | sed '$d')

# Check HTTP status code
if [ "$HTTP_CODE" != "200" ] && [ "$HTTP_CODE" != "201" ]; then
    print_error "Failed to obtain API token (HTTP $HTTP_CODE)"
    ERROR_MSG=$(echo "$TOKEN_RESPONSE" | jq -r '.error_description // .message // .error // empty' 2>/dev/null)
    if [ -n "$ERROR_MSG" ]; then
        print_error "Error: $ERROR_MSG"
    else
        print_error "Response: $TOKEN_RESPONSE"
    fi
    
    # Provide helpful hints based on status code
    case "$HTTP_CODE" in
        401|400)
            print_error "Hint: Authentication failed. Check username and password are correct."
            ;;
        404)
            print_error "Hint: Token endpoint not found. Verify the control plane URL: $CTRL_PLANE_URL"
            ;;
        000)
            print_error "Hint: Could not connect to server. Check the URL and network connection."
            print_error "      URL attempted: $CTRL_PLANE_URL/api/v1/token"
            ;;
    esac
    exit 1
fi

# Validate JSON response
if ! echo "$TOKEN_RESPONSE" | jq empty 2>/dev/null; then
    print_error "Received invalid JSON response from token endpoint"
    print_error "Response: $TOKEN_RESPONSE"
    exit 1
fi

USER_TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.accessToken // empty')

if [ -z "$USER_TOKEN" ]; then
    print_error "Failed to obtain API token - no accessToken in response"
    print_error "Response structure: $(echo "$TOKEN_RESPONSE" | jq -c 'keys' 2>/dev/null || echo 'Unable to parse')"
    exit 1
fi

print_success "API token obtained"
echo ""

# Step 2: Get System administrator role ID
print_info "Step 2: Finding System administrator role ID..."
ADMIN_ROLE_RESPONSE=$(curl -s -w "\n%{http_code}" "$CTRL_PLANE_URL/api/v1/authorization/roles" \
  -H "Authorization: Bearer $USER_TOKEN" 2>&1)

HTTP_CODE=$(echo "$ADMIN_ROLE_RESPONSE" | tail -n1)
ADMIN_ROLE=$(echo "$ADMIN_ROLE_RESPONSE" | sed '$d')

# Check HTTP status code
if [ "$HTTP_CODE" != "200" ]; then
    print_error "Failed to fetch roles (HTTP $HTTP_CODE)"
    ERROR_MSG=$(echo "$ADMIN_ROLE" | jq -r '.error_description // .message // .error // empty' 2>/dev/null)
    if [ -n "$ERROR_MSG" ]; then
        print_error "Error: $ERROR_MSG"
    else
        print_error "Response: $ADMIN_ROLE"
    fi
    
    # Provide helpful hints based on status code
    case "$HTTP_CODE" in
        401)
            print_error "Hint: Authentication failed. The token may have expired or be invalid."
            ;;
        403)
            print_error "Hint: Access forbidden. The user may not have permission to view roles."
            ;;
        404)
            print_error "Hint: Endpoint not found. Check the control plane URL is correct."
            ;;
        000)
            print_error "Hint: Could not connect to server. Check the URL and network connection."
            ;;
    esac
    exit 1
fi

# Validate JSON response
if ! echo "$ADMIN_ROLE" | jq empty 2>/dev/null; then
    print_error "Received invalid JSON response from roles endpoint"
    print_error "Response: $ADMIN_ROLE"
    exit 1
fi

# Check if response is an array
if ! echo "$ADMIN_ROLE" | jq -e 'type == "array"' >/dev/null 2>&1; then
    print_error "Expected array of roles but got different response structure"
    print_error "Response: $ADMIN_ROLE"
    exit 1
fi

ADMIN_ROLE_ID=$(echo "$ADMIN_ROLE" | jq -r '.[] | select(.name == "System administrator") | .id // empty')

if [ -z "$ADMIN_ROLE_ID" ]; then
    print_error "Failed to find System administrator role"
    print_info "Available roles:"
    echo "$ADMIN_ROLE" | jq -r '.[] | "  - \(.name) (ID: \(.id))"' 2>/dev/null || echo "$ADMIN_ROLE"
    exit 1
fi

print_success "System administrator role ID: $ADMIN_ROLE_ID"
echo ""

# Step 3: Get Tenant ID from JWT token
print_info "Step 3: Extracting Tenant ID from JWT token..."

# Validate JWT format (should have 3 parts separated by dots)
TOKEN_PARTS=$(echo "$USER_TOKEN" | tr '.' '\n' | wc -l)
if [ "$TOKEN_PARTS" -ne 3 ]; then
    print_error "Invalid JWT token format (expected 3 parts, got $TOKEN_PARTS)"
    print_error "Token received: ${USER_TOKEN:0:50}..." # Show first 50 chars
    exit 1
fi

# Extract payload from JWT
PAYLOAD=$(echo "$USER_TOKEN" | cut -d'.' -f2)
# Add padding if needed for base64 decoding
PADDING=$((4 - ${#PAYLOAD} % 4))
if [ $PADDING -ne 4 ]; then
    PAYLOAD="${PAYLOAD}$(printf '%*s' $PADDING | tr ' ' '=')"
fi

# Decode and parse JWT payload
DECODED_PAYLOAD=$(echo "$PAYLOAD" | base64 -d 2>/dev/null)
if [ $? -ne 0 ] || [ -z "$DECODED_PAYLOAD" ]; then
    print_error "Failed to decode JWT token payload"
    print_error "This may indicate a malformed token"
    exit 1
fi

# Validate JSON in decoded payload
if ! echo "$DECODED_PAYLOAD" | jq empty 2>/dev/null; then
    print_error "JWT payload is not valid JSON"
    print_error "Decoded payload: $DECODED_PAYLOAD"
    exit 1
fi

TENANT_ID=$(echo "$DECODED_PAYLOAD" | jq -r '.tenant_id // empty')

if [ -z "$TENANT_ID" ] || [ "$TENANT_ID" = "null" ]; then
    print_error "Failed to extract Tenant ID from JWT token"
    print_error "JWT payload claims: $(echo "$DECODED_PAYLOAD" | jq -c 'keys' 2>/dev/null || echo 'Unable to parse')"
    print_info "Note: The token may not contain a tenant_id claim, which could indicate insufficient permissions."
    exit 1
fi

print_success "Tenant ID: $TENANT_ID"
echo ""

# Step 4: Check existing access rules
print_info "Step 4: Checking existing permissions for $USERNAME..."
ACCESS_RULES_RESPONSE=$(curl -s -w "\n%{http_code}" "$CTRL_PLANE_URL/api/v1/authorization/access-rules?subjectId=$USERNAME&scopeType=tenant&scopeId=$TENANT_ID" \
  -H "Authorization: Bearer $USER_TOKEN" 2>&1)

HTTP_CODE=$(echo "$ACCESS_RULES_RESPONSE" | tail -n1)
ACCESS_RULES=$(echo "$ACCESS_RULES_RESPONSE" | sed '$d')

# Check HTTP status code
if [ "$HTTP_CODE" != "200" ]; then
    print_error "Failed to fetch existing access rules (HTTP $HTTP_CODE)"
    ERROR_MSG=$(echo "$ACCESS_RULES" | jq -r '.error_description // .message // .error // empty' 2>/dev/null)
    if [ -n "$ERROR_MSG" ]; then
        print_error "Error: $ERROR_MSG"
    else
        print_error "Response: $ACCESS_RULES"
    fi
    
    # Provide helpful hints based on status code
    case "$HTTP_CODE" in
        401)
            print_error "Hint: Authentication failed. The token may have expired."
            ;;
        403)
            print_error "Hint: Access forbidden. The user may not have permission to view access rules."
            ;;
        404)
            print_error "Hint: Endpoint not found. Check the control plane URL and API version."
            ;;
    esac
    exit 1
fi

# Validate JSON response
if ! echo "$ACCESS_RULES" | jq empty 2>/dev/null; then
    print_error "Received invalid JSON response from access rules endpoint"
    print_error "Response: $ACCESS_RULES"
    exit 1
fi

# Check if user already has System administrator role at tenant scope
HAS_ADMIN=$(echo "$ACCESS_RULES" | jq -r --argjson roleId "$ADMIN_ROLE_ID" \
  '.accessRules // [] | map(select(.roleId == $roleId and .scopeType == "tenant")) | length' 2>/dev/null)

if [ -z "$HAS_ADMIN" ]; then
    print_error "Failed to parse access rules response"
    print_error "Response structure: $(echo "$ACCESS_RULES" | jq -c 'keys' 2>/dev/null || echo 'Unable to parse')"
    exit 1
fi

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
VERIFY_RULES_RESPONSE=$(curl -s -w "\n%{http_code}" "$CTRL_PLANE_URL/api/v1/authorization/access-rules?subjectId=$USERNAME&scopeType=tenant&scopeId=$TENANT_ID" \
  -H "Authorization: Bearer $USER_TOKEN" 2>&1)

HTTP_CODE=$(echo "$VERIFY_RULES_RESPONSE" | tail -n1)
VERIFY_RULES=$(echo "$VERIFY_RULES_RESPONSE" | sed '$d')

# Check HTTP status code
if [ "$HTTP_CODE" != "200" ]; then
    print_error "Warning: Failed to verify permission (HTTP $HTTP_CODE)"
    ERROR_MSG=$(echo "$VERIFY_RULES" | jq -r '.error_description // .message // .error // empty' 2>/dev/null)
    if [ -n "$ERROR_MSG" ]; then
        print_error "Error: $ERROR_MSG"
    fi
    print_info "Permission was granted but verification failed. You can manually check the permissions in the UI."
else
    # Validate JSON response
    if ! echo "$VERIFY_RULES" | jq empty 2>/dev/null; then
        print_error "Warning: Received invalid JSON response during verification"
        print_info "Permission was granted but verification failed. You can manually check the permissions in the UI."
    else
        VERIFY_ADMIN=$(echo "$VERIFY_RULES" | jq -r --argjson roleId "$ADMIN_ROLE_ID" \
          '.accessRules // [] | map(select(.roleId == $roleId and .scopeType == "tenant")) | length' 2>/dev/null)

        if [ -n "$VERIFY_ADMIN" ] && [ "$VERIFY_ADMIN" -gt 0 ]; then
            print_success "Verified: System administrator permission is active"
        else
            print_error "Warning: Could not verify the permission was added"
            print_info "The grant request succeeded, but verification failed. Please check manually."
        fi
    fi
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
