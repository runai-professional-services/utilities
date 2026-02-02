#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to generate a secure random password
generate_password() {
    # Generate password with at least 1 digit, 1 lowercase, 1 uppercase, 1 special char
    local length=16
    
    # Define character sets
    local digits="0123456789"
    local lowercase="abcdefghijklmnopqrstuvwxyz"
    local uppercase="ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    local special="!@#$%^&*()-_=+"
    local all="${digits}${lowercase}${uppercase}${special}"
    
    # Build password character by character for better randomness
    local password=""
    
    # Add required characters first
    password+="${digits:RANDOM % ${#digits}:1}"
    password+="${lowercase:RANDOM % ${#lowercase}:1}"
    password+="${uppercase:RANDOM % ${#uppercase}:1}"
    password+="${special:RANDOM % ${#special}:1}"
    
    # Fill the rest with random characters from all sets
    for ((i=4; i<length; i++)); do
        password+="${all:RANDOM % ${#all}:1}"
    done
    
    # Simple shuffle using bash arrays (portable, no external commands needed)
    local chars=()
    for ((i=0; i<${#password}; i++)); do
        chars[$i]="${password:$i:1}"
    done
    
    # Fisher-Yates shuffle
    for ((i=${#chars[@]}-1; i>0; i--)); do
        local j=$((RANDOM % (i+1)))
        local temp="${chars[$i]}"
        chars[$i]="${chars[$j]}"
        chars[$j]="$temp"
    done
    
    # Reconstruct password
    local shuffled=""
    for char in "${chars[@]}"; do
        shuffled+="$char"
    done
    
    echo "$shuffled"
}

# Function to generate a random email
generate_email() {
    local random_string=$(cat /dev/urandom | LC_ALL=C tr -dc 'a-z0-9' | fold -w 8 | head -n 1)
    local timestamp=$(date +%s)
    echo "user-${random_string}-${timestamp}@runai.local"
}

# Configuration
USER_EMAIL="${1}"
USER_PASSWORD="${2}"
REALM="${3:-runai}"
RESET_PASSWORD="${4:-true}"
GRANT_ADMIN="${5:-true}"

# Generate random email if not provided
EMAIL_GENERATED=false
if [ -z "$USER_EMAIL" ]; then
    USER_EMAIL=$(generate_email)
    EMAIL_GENERATED=true
    echo -e "${YELLOW}ℹ No email provided - generated random email: $USER_EMAIL${NC}"
    echo ""
fi

# Generate random password if not provided
PASSWORD_GENERATED=false
if [ -z "$USER_PASSWORD" ]; then
    USER_PASSWORD=$(generate_password)
    PASSWORD_GENERATED=true
    echo -e "${YELLOW}ℹ No password provided - generated secure random password${NC}"
    echo ""
fi

# Usage function
usage() {
    echo "Usage: $0 [user_email] [password] [realm] [reset_password] [grant_admin]"
    echo ""
    echo "Arguments:"
    echo "  user_email       Optional. Email address for the new user (default: auto-generated)"
    echo "  password         Optional. User password (default: auto-generated)"
    echo "  realm            Optional. Keycloak realm / tenant name (default: runai)"
    echo "  reset_password   Optional. Force password reset on first login (default: true)"
    echo "  grant_admin      Optional. Grant System Administrator role (default: true)"
    echo ""
    echo "Examples:"
    echo "  $0                              # Generate random email and password"
    echo "  $0 newuser@example.com          # Specify email, generate password"
    echo "  $0 newuser@example.com MyPass123  # Specify both email and password"
    echo "  $0 user@example.com MyPass123 runai false true  # Full options"
    exit 1
}

# Validate email format
if ! echo "$USER_EMAIL" | grep -qE '^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'; then
    echo -e "${RED}Error: Invalid email format: $USER_EMAIL${NC}"
    exit 1
fi

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Run:AI User Creation Script${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Configuration:"
if [ "$EMAIL_GENERATED" = true ]; then
    echo "  Email:          $USER_EMAIL (auto-generated)"
else
    echo "  Email:          $USER_EMAIL"
fi
if [ "$PASSWORD_GENERATED" = true ]; then
    echo "  Password:       ${USER_PASSWORD:0:3}**** (auto-generated)"
else
    echo "  Password:       ${USER_PASSWORD:0:3}****"
fi
echo "  Realm:          $REALM"
echo "  Reset Password: $RESET_PASSWORD"
echo "  Grant Admin:    $GRANT_ADMIN"
echo ""

# Namespace where identity-manager is running
NAMESPACE="runai-backend"

# Test kubectl connectivity
echo -e "${YELLOW}Testing cluster connectivity...${NC}"
if ! kubectl get namespace $NAMESPACE &>/dev/null; then
    echo -e "${RED}Error: Cannot connect to cluster or namespace $NAMESPACE does not exist${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Cluster connectivity OK${NC}"
echo ""

# Find required pods
echo -e "${YELLOW}Finding required pods...${NC}"
IDENTITY_POD=$(kubectl get pod -n $NAMESPACE -l app.kubernetes.io/name=identity-manager -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
AUTHORIZATION_POD=$(kubectl get pod -n $NAMESPACE -l app.kubernetes.io/name=authorization -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
TENANTS_POD=$(kubectl get pod -n $NAMESPACE -l app.kubernetes.io/name=tenants-manager -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [ -z "$IDENTITY_POD" ]; then
    echo -e "${RED}Error: Identity-manager pod not found in namespace $NAMESPACE${NC}"
    exit 1
fi

if [ -z "$AUTHORIZATION_POD" ] && [ "$GRANT_ADMIN" = "true" ]; then
    echo -e "${RED}Error: Authorization pod not found in namespace $NAMESPACE${NC}"
    exit 1
fi

if [ -z "$TENANTS_POD" ] && [ "$GRANT_ADMIN" = "true" ]; then
    echo -e "${RED}Error: Tenants-manager pod not found in namespace $NAMESPACE${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Identity-manager pod: $IDENTITY_POD${NC}"
if [ "$GRANT_ADMIN" = "true" ]; then
    echo -e "${GREEN}✓ Authorization pod: $AUTHORIZATION_POD${NC}"
    echo -e "${GREEN}✓ Tenants-manager pod: $TENANTS_POD${NC}"
fi
echo ""

# Auto-detect tenant ID from realm/tenant name
if [ "$GRANT_ADMIN" = "true" ]; then
    echo -e "${YELLOW}Auto-detecting tenant ID from realm '$REALM'...${NC}"
    TENANT_RESPONSE=$(kubectl exec -n $NAMESPACE $TENANTS_POD -- sh -c "
    curl -s 'http://localhost:8080/internal/api/v1/tenants?tenantName=$REALM'
    " 2>&1 | grep -v "Defaulted container")
    
    TENANT_ID=$(echo "$TENANT_RESPONSE" | jq -r '.id' 2>/dev/null)
    
    if [ -z "$TENANT_ID" ] || [ "$TENANT_ID" = "null" ]; then
        echo -e "${RED}Error: Could not auto-detect tenant ID for realm '$REALM'${NC}"
        echo "Response: $TENANT_RESPONSE"
        exit 1
    fi
    
    echo -e "${GREEN}✓ Tenant ID detected: $TENANT_ID${NC}"
    echo ""
fi

# Create user via internal API
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Creating User${NC}"
echo -e "${GREEN}========================================${NC}"

RESPONSE=$(kubectl exec -n $NAMESPACE $IDENTITY_POD -- sh -c "
curl -X POST http://localhost:8080/internal/users \
  -H 'Content-Type: application/json' \
  -d '{
    \"email\": \"$USER_EMAIL\",
    \"realm\": \"$REALM\",
    \"password\": \"$USER_PASSWORD\",
    \"resetPassword\": $RESET_PASSWORD
  }' \
  -w '\n__HTTP_CODE__%{http_code}' \
  -s
" 2>&1)

# Extract HTTP code and response body
HTTP_CODE=$(echo "$RESPONSE" | grep -o '__HTTP_CODE__[0-9]*' | sed 's/__HTTP_CODE__//')
BODY=$(echo "$RESPONSE" | sed 's/__HTTP_CODE__[0-9]*$//')

echo "Response: $BODY"
echo ""

if [ "$HTTP_CODE" = "201" ]; then
    echo -e "${GREEN}✓ User created successfully in Keycloak${NC}"
    USER_CREATED=true
elif [ "$HTTP_CODE" = "409" ]; then
    echo -e "${YELLOW}⚠ User already exists in Keycloak${NC}"
    USER_CREATED=false
else
    echo -e "${RED}✗ Failed to create user${NC}"
    echo "HTTP Status Code: $HTTP_CODE"
    echo "Response: $BODY"
    exit 1
fi
echo ""

# Step 2: Grant System Administrator permissions
if [ "$GRANT_ADMIN" = "true" ]; then
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}Step 2: Granting System Administrator Access${NC}"
    echo -e "${GREEN}========================================${NC}"

    # Use internal endpoint (no auth required)
    ACCESS_RESPONSE=$(kubectl exec -n $NAMESPACE $AUTHORIZATION_POD -- sh -c "
    curl -X POST http://localhost:8080/internal/authorization/access-rules \
      -H 'Content-Type: application/json' \
      -H 'X-Runai-Tenant-Id: $TENANT_ID' \
      -d '{
        \"subjectId\": \"$USER_EMAIL\",
        \"subjectType\": \"user\",
        \"roleName\": \"System administrator\",
        \"scope\": {
          \"id\": \"$TENANT_ID\",
          \"type\": \"tenant\",
          \"name\": \"$REALM\"
        }
      }' \
      -w '\n__HTTP_CODE__%{http_code}' \
      -s
    " 2>&1)

    # Extract HTTP code and response body
    ACCESS_HTTP_CODE=$(echo "$ACCESS_RESPONSE" | grep -o '__HTTP_CODE__[0-9]*' | sed 's/__HTTP_CODE__//')
    ACCESS_BODY=$(echo "$ACCESS_RESPONSE" | sed 's/__HTTP_CODE__[0-9]*$//')

    echo "Response: $ACCESS_BODY"
    echo ""

    if [ "$ACCESS_HTTP_CODE" = "201" ]; then
        echo -e "${GREEN}✓ Access rule creation API returned success${NC}"
    else
        echo -e "${YELLOW}⚠ Warning: Access rule creation failed${NC}"
        echo "HTTP Status Code: $ACCESS_HTTP_CODE"
        echo "Response: $ACCESS_BODY"
    fi
    echo ""
    
    # Verify the permissions were actually created
    echo -e "${YELLOW}Verifying permissions...${NC}"
    VERIFY_RESPONSE=$(kubectl exec -n $NAMESPACE $AUTHORIZATION_POD -- sh -c "
    curl -X GET 'http://localhost:8080/internal/authorization/subject-access-rules?subjectType=user&subjectIds=$USER_EMAIL' \
      -H 'X-Runai-Tenant-Id: $TENANT_ID' \
      -s
    " 2>&1)
    
    # Filter out the "Defaulted container" message
    VERIFY_CLEAN=$(echo "$VERIFY_RESPONSE" | grep -v "Defaulted container")
    
    echo "User's access rules:"
    echo "$VERIFY_CLEAN" | jq -r '.[] | "  - Role: \(.roleName), Scope: \(.scopeType) (\(.scopeName // .scopeId))"' 2>/dev/null || echo "$VERIFY_CLEAN"
    echo ""
    
    # Check if System administrator role exists
    if echo "$VERIFY_CLEAN" | grep -q "System administrator"; then
        echo -e "${GREEN}✓ System Administrator permissions created!${NC}"
        echo ""
        echo -e "${GREEN}The user now has tenant-wide System Administrator access for:${NC}"
        echo "  - Run:AI UI"
        echo "  - Run:AI API"
        echo "  - CLI operations"
    else
        echo -e "${RED}✗ System Administrator permissions NOT found!${NC}"
        echo -e "${YELLOW}The access rule may not have been created properly.${NC}"
        echo ""
        echo -e "${YELLOW}ERROR: You may need to grant permissions manually via the Run:AI UI${NC}"
    fi
    echo ""
fi

# Final summary
echo -e "${GREEN}========================================${NC}"
if [ "$USER_CREATED" = true ]; then
    echo -e "${GREEN}✓ User Created Successfully!${NC}"
else
    echo -e "${GREEN}✓ User Configuration Updated${NC}"
fi
echo -e "${GREEN}========================================${NC}"
echo ""
echo "User Details:"
echo "  Email:              $USER_EMAIL"
echo "  Password:           $USER_PASSWORD"
echo "  Realm:              $REALM"
echo "  Reset Password:     $RESET_PASSWORD"
if [ "$GRANT_ADMIN" = "true" ]; then
    echo "  Role:               System Administrator (Tenant-wide)"
    echo "  Tenant ID:          $TENANT_ID"
fi
echo ""
if [ "$EMAIL_GENERATED" = true ] || [ "$PASSWORD_GENERATED" = true ]; then
    echo -e "${YELLOW}Important:${NC}"
    if [ "$EMAIL_GENERATED" = true ]; then
        echo "  • Email was auto-generated - save these credentials!"
    fi
    if [ "$PASSWORD_GENERATED" = true ]; then
        echo "  • Password was auto-generated - save it securely!"
    fi
    if [ "$RESET_PASSWORD" = "true" ]; then
        echo "  • User will be prompted to change password on first login"
    fi
    echo ""
elif [ "$RESET_PASSWORD" = "true" ]; then
    echo -e "${YELLOW}Important:${NC}"
    echo "  • The user will be prompted to change their password on first login"
    echo ""
fi
echo -e "${GREEN}User can now login to Run:AI!${NC}"
exit 0
