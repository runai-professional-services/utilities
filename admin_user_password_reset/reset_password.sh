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

# Generate a random password that meets complexity requirements
generate_password() {
    local length=16
    local lowercase='abcdefghijklmnopqrstuvwxyz'
    local uppercase='ABCDEFGHIJKLMNOPQRSTUVWXYZ'
    local digits='0123456789'
    local special='!@#$%^&*-_=+'
    
    # Ensure at least one character from each required category
    local password=""
    password+="${lowercase:RANDOM%${#lowercase}:1}"
    password+="${uppercase:RANDOM%${#uppercase}:1}"
    password+="${digits:RANDOM%${#digits}:1}"
    password+="${special:RANDOM%${#special}:1}"
    
    # Fill the rest with random characters from all categories
    local all_chars="${lowercase}${uppercase}${digits}${special}"
    for ((i=4; i<length; i++)); do
        password+="${all_chars:RANDOM%${#all_chars}:1}"
    done
    
    # Shuffle the password to randomize character positions
    echo "$password" | fold -w1 | shuf | tr -d '\n'
}

# Usage function
usage() {
    echo "Usage: $0 [--username <USERNAME>] [--namespace <NAMESPACE>] [--url <RUNAI_URL>]"
    echo ""
    echo "Options:"
    echo "  --username    Username to reset password for (default: test@run.ai)"
    echo "  --namespace   Kubernetes namespace (default: runai-backend)"
    echo "  --url         Run:ai control plane URL (will try to auto-detect if not provided)"
    echo ""
    echo "Note: A secure random password will be automatically generated and displayed after reset."
    echo ""
    echo "Example:"
    echo "  $0"
    echo "  $0 --username test@run.ai"
    exit 1
}

# Parse arguments
NAMESPACE="runai-backend"
USERNAME="test@run.ai"
RUNAI_URL=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --username)
            USERNAME="$2"
            shift 2
            ;;
        --namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        --url)
            RUNAI_URL="$2"
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

# Generate a secure random password
NEW_PASSWORD=$(generate_password)

echo "=========================================="
echo "Run:ai Admin Password Reset Tool"
echo "=========================================="
echo ""

# Check kubectl is available
if ! command -v kubectl &> /dev/null; then
    print_error "kubectl is not installed or not in PATH"
    exit 1
fi

# Check jq is available
if ! command -v jq &> /dev/null; then
    print_error "jq is not installed or not in PATH"
    exit 1
fi

# Check curl is available
if ! command -v curl &> /dev/null; then
    print_error "curl is not installed or not in PATH"
    exit 1
fi

print_info "Target username: $USERNAME"
print_info "Namespace: $NAMESPACE"
print_info "Generating secure random password..."
echo ""

# Step 1: Get Keycloak admin credentials
print_info "Step 1: Retrieving Keycloak admin credentials from Kubernetes..."
KC_ADMIN_USER=$(kubectl get secret runai-backend-keycloakx -n "$NAMESPACE" -o jsonpath='{.data.KEYCLOAK_ADMIN}' 2>/dev/null | base64 -d)
KC_ADMIN_PASS=$(kubectl get secret runai-backend-keycloakx -n "$NAMESPACE" -o jsonpath='{.data.KEYCLOAK_ADMIN_PASSWORD}' 2>/dev/null | base64 -d)

if [ -z "$KC_ADMIN_USER" ] || [ -z "$KC_ADMIN_PASS" ]; then
    print_error "Failed to retrieve Keycloak admin credentials from secret 'runai-backend-keycloakx'"
    exit 1
fi

print_success "Keycloak admin credentials retrieved"
echo ""

# Step 2: Auto-detect Run:ai URL if not provided
if [ -z "$RUNAI_URL" ]; then
    print_info "Step 2: Auto-detecting Run:ai control plane URL..."
    RUNAI_URL=$(kubectl get configmap runai-backend-tenants-manager -n "$NAMESPACE" -o jsonpath='{.data.TENANT_DOMAIN_TEMPLATE}' 2>/dev/null)
    
    if [ -z "$RUNAI_URL" ]; then
        print_error "Failed to auto-detect Run:ai URL. Please provide it with --url parameter"
        exit 1
    fi
    
    print_success "Run:ai URL detected: $RUNAI_URL"
else
    print_info "Step 2: Using provided Run:ai URL: $RUNAI_URL"
fi

KEYCLOAK_URL="${RUNAI_URL}/auth"
echo ""

# Step 3: Get Keycloak admin token
print_info "Step 3: Obtaining Keycloak admin token..."
KC_TOKEN=$(curl -s -X POST "$KEYCLOAK_URL/realms/master/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "username=$KC_ADMIN_USER" \
  -d "password=$KC_ADMIN_PASS" \
  -d "grant_type=password" \
  -d "client_id=admin-cli" 2>/dev/null | jq -r '.access_token')

if [ -z "$KC_TOKEN" ] || [ "$KC_TOKEN" = "null" ]; then
    print_error "Failed to obtain Keycloak admin token"
    exit 1
fi

print_success "Keycloak admin token obtained"
echo ""

# Step 4: Find the user in Keycloak
print_info "Step 4: Finding user '$USERNAME' in Keycloak..."
USER_DATA=$(curl -s "$KEYCLOAK_URL/admin/realms/runai/users?username=$USERNAME&exact=true" \
  -H "Authorization: Bearer $KC_TOKEN" 2>/dev/null)

USER_ID=$(echo "$USER_DATA" | jq -r '.[0].id')

if [ -z "$USER_ID" ] || [ "$USER_ID" = "null" ]; then
    print_error "User '$USERNAME' not found in Keycloak"
    exit 1
fi

print_success "User found (ID: $USER_ID)"
echo ""

# Step 5: Reset the password
print_info "Step 5: Resetting password for user '$USERNAME'..."
HTTP_CODE=$(curl -s -w "%{http_code}" -o /dev/null -X PUT \
  "$KEYCLOAK_URL/admin/realms/runai/users/$USER_ID/reset-password" \
  -H "Authorization: Bearer $KC_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"type\": \"password\",
    \"temporary\": false,
    \"value\": \"$NEW_PASSWORD\"
  }")

if [ "$HTTP_CODE" != "204" ]; then
    print_error "Failed to reset password (HTTP $HTTP_CODE)"
    exit 1
fi

print_success "Password reset successfully"
echo ""

# Step 6: Verify the new password works
print_info "Step 6: Verifying new password by obtaining Run:ai API token..."
RUNAI_TOKEN=$(curl -s -X POST "$RUNAI_URL/api/v1/token" \
  -H "Content-Type: application/json" \
  -d "{
    \"grantType\": \"password\",
    \"clientID\": \"cli\",
    \"username\": \"$USERNAME\",
    \"password\": \"$NEW_PASSWORD\"
  }" 2>/dev/null | jq -r '.accessToken')

if [ -z "$RUNAI_TOKEN" ] || [ "$RUNAI_TOKEN" = "null" ]; then
    print_error "Failed to verify new password - could not obtain Run:ai API token"
    exit 1
fi

print_success "New password verified successfully"
echo ""

echo "=========================================="
print_success "Password reset completed successfully!"
echo "=========================================="
echo ""
echo "Login Credentials:"
echo "  Username: $USERNAME"
echo "  Password: $NEW_PASSWORD"
echo ""
echo "Run:ai URL: $RUNAI_URL"
echo ""
print_info "IMPORTANT: This is a randomly generated password."
print_info "Please login and change it to a more personal password in the UI."
print_info "Go to: User Settings → Change Password"
