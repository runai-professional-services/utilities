#!/usr/bin/env python3
import requests
import json
import os
import sys
from typing import Optional, Dict, List, Any

# Configuration - Update these values or set as environment variables
RUNAI_CTRL_PLANE_URL = os.getenv("RUNAI_CTRL_PLANE_URL", "")
RUNAI_USERNAME = os.getenv("RUNAI_USERNAME", "")  # local sys admin user
RUNAI_PASSWORD = os.getenv("RUNAI_PASSWORD", "")  # local sys admin password
TARGET_USER_EMAIL = os.getenv("TARGET_USER_EMAIL", "")  # Email of user to assign role to

# Validate required configuration
if not all([RUNAI_CTRL_PLANE_URL, RUNAI_USERNAME, RUNAI_PASSWORD]):
    print("Error: Missing required configuration. Please set:")
    print("- RUNAI_CTRL_PLANE_URL")
    print("- RUNAI_USERNAME")
    print("- RUNAI_PASSWORD")
    print("- TARGET_USER_EMAIL (email of user to assign the role to)")
    print("Either in the script or as environment variables.")
    sys.exit(1)

if not TARGET_USER_EMAIL:
    print("Warning: TARGET_USER_EMAIL not set. Will use tenant UUID as fallback.")
    print("Set TARGET_USER_EMAIL environment variable to assign role to a specific user.")

def get_bearer_token() -> str:
    """Get authentication token using password grant"""
    token_url = f"{RUNAI_CTRL_PLANE_URL}/api/v1/token"
    payload = {
        "grantType": "password",
        "clientID": "cli",
        "username": RUNAI_USERNAME,
        "password": RUNAI_PASSWORD
    }
    headers = {
        "Accept": "*/*",
        "Content-Type": "application/json"
    }
    try:
        response = requests.post(token_url, json=payload, headers=headers, timeout=30)
        response.raise_for_status()
        token_data = response.json()
        if "accessToken" not in token_data:
            raise ValueError("Access token not found in response")
        return token_data["accessToken"]
    except requests.exceptions.RequestException as e:
        print(f"Error getting authentication token: {e}")
        raise
    except (ValueError, KeyError) as e:
        print(f"Error parsing token response: {e}")
        raise

def get_tenant_info() -> tuple[str, str]:
    """Get tenant information from API"""
    try:
        token = get_bearer_token()
        url = f"{RUNAI_CTRL_PLANE_URL}/api/v1/tenants"
        headers = {
            "Accept": "application/json, text/plain, */*",
            "Authorization": f"Bearer {token}"
        }
        response = requests.get(url, headers=headers, timeout=30)
        response.raise_for_status()
        
        tenants = response.json()
        if not tenants or not isinstance(tenants, list):
            raise ValueError("No tenants found or invalid response format")
        
        # Use the first tenant (assuming single tenant setup)
        tenant = tenants[0]
        if "id" not in tenant or "uuid" not in tenant or "name" not in tenant:
            raise ValueError("Tenant missing required fields (id, uuid, name)")
            
        tenant_id = str(tenant["id"])
        test_user_id = tenant["uuid"]
        
        print(f"Found tenant: {tenant['name']} (ID: {tenant_id}, UUID: {test_user_id})")
        return tenant_id, test_user_id
    except requests.exceptions.RequestException as e:
        print(f"Error getting tenant information: {e}")
        raise
    except (ValueError, KeyError, IndexError) as e:
        print(f"Error parsing tenant response: {e}")
        raise

def enable_custom_rbac() -> requests.Response:
    """Enable custom RBAC feature flag"""
    try:
        url = f"{RUNAI_CTRL_PLANE_URL}/v1/k8s/setting"
        token = get_bearer_token()
        headers = {
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json"
        }
        payload = {
            "key": "tenant.enable_custom_roles",
            "source": "Tenant",
            "category": "Tenant",
            "label": "Custom Roles",
            "description": "Enable Custom Role Creation",
            "type": "Boolean",
            "value": True,
            "enable": True
        }
        response = requests.put(url, headers=headers, json=payload, timeout=30)
        print(f"Enable custom RBAC: {response.status_code}")
        if response.status_code not in [200, 201, 204]:
            print(f"Warning: Unexpected status code when enabling RBAC: {response.text}")
        return response
    except requests.exceptions.RequestException as e:
        print(f"Error enabling custom RBAC: {e}")
        raise

def get_existing_role(role_id: int) -> Optional[Dict[str, Any]]:
    """Get existing role configuration"""
    try:
        token = get_bearer_token()
        url = f"{RUNAI_CTRL_PLANE_URL}/api/v2/authorization/roles/{role_id}"
        headers = {
            "Authorization": f"Bearer {token}",
            "Accept": "application/json"
        }
        response = requests.get(url, headers=headers, timeout=30)
        if response.status_code == 200:
            return response.json()
        elif response.status_code == 404:
            print(f"Role {role_id} not found")
            return None
        else:
            print(f"Failed to get role {role_id}: {response.status_code} - {response.text}")
            return None
    except requests.exceptions.RequestException as e:
        print(f"Error getting role {role_id}: {e}")
        return None

def find_existing_role_by_name(role_name: str) -> Optional[Dict[str, Any]]:
    """Find existing role by name"""
    try:
        token = get_bearer_token()
        url = f"{RUNAI_CTRL_PLANE_URL}/api/v2/authorization/roles"
        headers = {
            "Authorization": f"Bearer {token}",
            "Accept": "application/json"
        }
        response = requests.get(url, headers=headers, timeout=30)
        if response.status_code == 200:
            roles = response.json()
            if not isinstance(roles, list):
                print(f"Unexpected response format for roles list: {type(roles)}")
                return None
            for role in roles:
                if isinstance(role, dict) and role.get("name") == role_name:
                    return role
            return None
        else:
            print(f"Failed to list roles: {response.status_code} - {response.text}")
            return None
    except requests.exceptions.RequestException as e:
        print(f"Error listing roles: {e}")
        return None

def create_combined_custom_role() -> Optional[Dict[str, Any]]:
    """Create the custom role combining 6 predefined roles"""
    try:
        # Get tenant info
        tenant_id, _ = get_tenant_info()
        
        # Generate a unique role name with timestamp
        import datetime
        timestamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
        role_name = f"tue researcher current {timestamp}"
        
        # Role IDs to combine
        role_ids = [10, 11, 9, 8, 6, 13]  # Credentials, Data source, Environment, L2 researcher, ML engineer, Template admins
        combined_permissions = []
        
        print("Fetching permissions from existing roles...")
        for role_id in role_ids:
            role = get_existing_role(role_id)
            if role and "permissions" in role:
                combined_permissions.extend(role["permissions"])
                print(f"Added permissions from role: {role.get('name', f'Role {role_id}')}")
            else:
                print(f"Failed to retrieve role with ID: {role_id} or role has no permissions")
        
        # Remove duplicate permissions based on resourceType and groupId
        unique_permissions = []
        seen_permissions = set()
        
        for perm in combined_permissions:
            if not isinstance(perm, dict):
                print(f"Warning: Invalid permission format: {perm}")
                continue
                
            perm_key = (perm.get("resourceType"), perm.get("groupId"))
            if perm_key not in seen_permissions:
                seen_permissions.add(perm_key)
                unique_permissions.append(perm)
            else:
                # Merge actions for duplicate permissions
                existing_perm = next((p for p in unique_permissions 
                                    if (p.get("resourceType"), p.get("groupId")) == perm_key), None)
                if existing_perm:
                    existing_actions = set(existing_perm.get("actions", []))
                    new_actions = set(perm.get("actions", []))
                    existing_perm["actions"] = list(existing_actions.union(new_actions))
    
        # Create the new combined role
        token = get_bearer_token()
        url = f"{RUNAI_CTRL_PLANE_URL}/api/v2/authorization/roles"
        headers = {
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json"
        }
        
        payload = {
            "name": role_name,
            "description": "Combined role with permissions from Credentials administrator, Data source administrator, Environment administrator, L2 researcher, ML engineer, and Template administrator",
            "permissions": unique_permissions,
            "scopeType": "tenant",
            "scopeId": tenant_id,
            "enabled": True,
            "kubernetesPermissions": {
                "predefinedRole": "8"
            },
        }
    
        print(f"Creating role with name: {role_name}")
        print(f"Role will have {len(unique_permissions)} unique permissions")
        
        response = requests.post(url, headers=headers, json=payload, timeout=30)
        print(f"Create custom role: {response.status_code}")
        
        if response.status_code == 201:
            role_data = response.json()
            print(f"Created role with ID: {role_data.get('id')}")
            print(f"\n=== Created Custom Role Details ===")
            print(f"Name: {role_data.get('name')}")
            print(f"Description: {role_data.get('description')}")
            print(f"ID: {role_data.get('id')}")
            print(f"Scope Type: {role_data.get('scopeType')}")
            print(f"Scope ID: {role_data.get('scopeId')}")
            print(f"Enabled: {role_data.get('enabled')}")
            print(f"Total Permissions: {len(role_data.get('permissions', []))}")
            
            print(f"\n=== Role Permissions Breakdown ===")
            permissions = role_data.get('permissions', [])
            for i, perm in enumerate(permissions, 1):
                print(f"{i:2d}. Resource: {perm.get('resourceType', 'N/A'):<25} "
                      f"Group: {perm.get('groupId', 'N/A'):<15} "
                      f"Actions: {', '.join(perm.get('actions', []))}")
            
            return role_data
        elif response.status_code == 409:
            print(f"Role creation failed - Conflict (409): {response.text}")
            print("This usually means a role with the same name already exists.")
            print("Checking if role already exists...")
            
            # Try to find existing role with the same name
            existing_role = find_existing_role_by_name(role_name)
            if existing_role:
                print(f"Found existing role with ID: {existing_role.get('id')}")
                print("Using existing role instead of creating new one.")
                
                print(f"\n=== Existing Custom Role Details ===")
                print(f"Name: {existing_role.get('name')}")
                print(f"Description: {existing_role.get('description')}")
                print(f"ID: {existing_role.get('id')}")
                print(f"Scope Type: {existing_role.get('scopeType')}")
                print(f"Scope ID: {existing_role.get('scopeId')}")
                print(f"Enabled: {existing_role.get('enabled')}")
                print(f"Total Permissions: {len(existing_role.get('permissions', []))}")
                
                print(f"\n=== Role Permissions Breakdown ===")
                permissions = existing_role.get('permissions', [])
                for i, perm in enumerate(permissions, 1):
                    print(f"{i:2d}. Resource: {perm.get('resourceType', 'N/A'):<25} "
                          f"Group: {perm.get('groupId', 'N/A'):<15} "
                          f"Actions: {', '.join(perm.get('actions', []))}")
                
                return existing_role
            else:
                print("Could not find existing role. You may need to delete the conflicting role or use a different name.")
                return None
        else:
            print(f"Error creating role (HTTP {response.status_code}): {response.text}")
            try:
                error_data = response.json()
                print(f"Error details: {json.dumps(error_data, indent=2)}")
            except:
                print("Could not parse error response as JSON")
            return None
    except Exception as e:
        print(f"Unexpected error creating custom role: {e}")
        return None

def assign_role_to_user(role_id: str, user_identifier: str, is_email: bool = False) -> requests.Response:
    """Assign custom role to user
    
    Args:
        role_id: The ID of the role to assign
        user_identifier: Either user email or user ID
        is_email: True if user_identifier is an email, False if it's a user ID
    """
    try:
        # Get tenant info
        tenant_id, _ = get_tenant_info()
        
        token = get_bearer_token()
        url = f"{RUNAI_CTRL_PLANE_URL}/api/v1/access-rules"
        headers = {
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json"
        }
        
        # Use the new access rules API format based on the documentation
        if is_email:
            payload = {
                "subjectId": user_identifier,
                "subjectType": "user",
                "roleId": int(role_id),
                "scopeType": "tenant",
                "scopeId": tenant_id
            }
            print(f"Assigning role {role_id} to user: {user_identifier}")
        else:
            # Fallback to old format for backwards compatibility
            payload = {
                "userId": user_identifier,
                "roleId": role_id,
                "scopeType": "tenant",
                "scopeId": tenant_id
            }
            print(f"Assigning role {role_id} to user ID: {user_identifier}")
        
        response = requests.post(url, headers=headers, json=payload, timeout=30)
        print(f"Assign role to user: {response.status_code}")
        
        if response.status_code not in [200, 201]:
            print(f"Error assigning role: {response.text}")
            try:
                error_data = response.json()
                print(f"Error details: {json.dumps(error_data, indent=2)}")
            except:
                print("Could not parse error response as JSON")
        else:
            if is_email:
                print(f"Successfully assigned role to user: {user_identifier}")
            else:
                print(f"Successfully assigned role to user ID: {user_identifier}")
        
        return response
    except requests.exceptions.RequestException as e:
        print(f"Error assigning role to user: {e}")
        raise

def compare_with_l2_researcher(custom_role_id: str) -> None:
    """Compare permissions and assign L2 researcher for testing"""
    try:
        l2_researcher = get_existing_role(8)  # L2 researcher role ID
        
        if l2_researcher and "permissions" in l2_researcher:
            print("\n=== L2 Researcher Permissions ===")
            for perm in l2_researcher["permissions"]:
                if isinstance(perm, dict):
                    print(f"- Actions: {perm.get('actions', [])}, Resource: {perm.get('resourceType')}, Group: {perm.get('groupId')}")
        else:
            print("Could not retrieve L2 researcher role permissions")
        
        # Assign L2 researcher role in addition to custom role for comparison
        print("\nAssigning L2 researcher role for comparison...")
        if TARGET_USER_EMAIL:
            assign_role_to_user("8", TARGET_USER_EMAIL, is_email=True)
        else:
            # Fallback to tenant UUID if no email specified
            _, test_user_id = get_tenant_info()
            assign_role_to_user("8", test_user_id, is_email=False)
    except Exception as e:
        print(f"Error comparing with L2 researcher: {e}")

def main() -> None:
    """Main reproduction workflow"""
    try:
        print("=== Custom RBAC Issue Reproduction Script ===\n")
        
        # Get tenant info at the start
        print("0. Getting tenant information...")
        tenant_id, test_user_id = get_tenant_info()
        
        # Step 1: Enable custom RBAC
        print("\n1. Enabling custom RBAC feature...")
        enable_custom_rbac()
        
        # Step 2: Create combined custom role
        print("\n2. Creating combined custom role...")
        custom_role = create_combined_custom_role()
        
        if not custom_role or "id" not in custom_role:
            print("Failed to create custom role. Exiting.")
            return
        
        # Step 3: Assign role to user
        if TARGET_USER_EMAIL:
            print(f"\n3. Assigning custom role to user {TARGET_USER_EMAIL}...")
            assign_role_to_user(custom_role["id"], TARGET_USER_EMAIL, is_email=True)
        else:
            print(f"\n3. Assigning custom role to user {test_user_id} (tenant UUID fallback)...")
            assign_role_to_user(custom_role["id"], test_user_id, is_email=False)
        
        # Step 4: Compare with L2 researcher
        print("\n4. Comparing with L2 researcher role...")
        compare_with_l2_researcher(custom_role["id"])
        
        print("\n=== Reproduction Setup Complete ===")
        print("Next steps for manual testing:")
        print("1. Login as the test user")
        print("2. Submit a workload/job")
        print("3. Try to view logs in Web GUI (should fail)")
        print("4. Try to view logs via CLI (should work)")
        print("5. The L2 researcher role has been added - logs should now work in GUI")
    except KeyboardInterrupt:
        print("\nScript interrupted by user")
        sys.exit(1)
    except Exception as e:
        print(f"\nFatal error: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()