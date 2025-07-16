from pathlib import Path
import requests
import json
import csv
import os
import sys
import yaml
import string

# Run AI Configuration
RUN_AI_APP_CLIENT_ID = os.getenv('RUN_AI_APP_CLIENT_ID')
RUN_AI_APP_CLIENT_SECRET = os.getenv('RUN_AI_APP_CLIENT_SECRET')
RUN_AI_CLUSTER_ID = os.getenv('RUN_AI_CLUSTER_ID')
RUN_AI_BASE_URL = os.getenv('RUN_AI_BASE_URL')
RUN_AI_TOKEN_API = f"{RUN_AI_BASE_URL}/api/v1/token"
RUN_AI_POLICY_API = f"{RUN_AI_BASE_URL}/api/v2/policy"

# File Configuration
CSV_FILE_PATH = 'project_list.csv'

# =============================================================================

class APIPolicyRequest:
    def __init__(self):
        self.app_client_id = RUN_AI_APP_CLIENT_ID
        self.app_client_secret = RUN_AI_APP_CLIENT_SECRET
        self.clusterid = RUN_AI_CLUSTER_ID
        self.csv_file = CSV_FILE_PATH
        self.token = None
        self.templates = {}
        
        # Validate required inputs
        if not self.app_client_id or not self.app_client_secret or not self.clusterid:
            print("Error: Missing required credentials. Set RUN_AI_APP_CLIENT_ID, RUN_AI_APP_CLIENT_SECRET, and RUN_AI_CLUSTER_ID environment variables or modify the configuration section above.")
            sys.exit(1)
            
        if not os.path.exists(self.csv_file):
            print(f"Error: CSV file not found: {self.csv_file}")
            sys.exit(1)
            
        # Load YAML templates
        self.load_templates()

    def load_templates(self):
        """Load YAML templates from the current directory"""
        try:
            # Load distributed template
            distributed_template_path = 'policy_template_distributed.yaml'
            if os.path.exists(distributed_template_path):
                with open(distributed_template_path, 'r') as f:
                    self.templates['distributed'] = yaml.safe_load(f)
            else:
                print(f"Warning: Distributed template not found at {distributed_template_path}")
                
            # Load standard template
            standard_template_path = 'policy_template_standard.yaml'
            if os.path.exists(standard_template_path):
                with open(standard_template_path, 'r') as f:
                    self.templates['standard'] = yaml.safe_load(f)
            else:
                print(f"Warning: Standard template not found at {standard_template_path}")
                
            print("Templates loaded successfully")
            
        except Exception as e:
            print(f"Error loading templates: {e}")
            sys.exit(1)

    def replace_template_variables(self, template, variables):
        """Replace placeholders in template with actual values"""
        template_str = yaml.dump(template, default_flow_style=False)
        
        try:
            # Replace placeholders with actual values
            result_str = template_str
            result_str = result_str.replace('PROJECT_ID_PLACEHOLDER', str(variables['project_id']))
            result_str = result_str.replace('PROJECT_NAME_PLACEHOLDER', str(variables['project_name']))
            result_str = result_str.replace('USER_HOME_DIR_PLACEHOLDER', str(variables['user_home_dir']))
            result_str = result_str.replace('TYPE_POLICY_PLACEHOLDER', str(variables['type_policy']))
            
            # Convert back to YAML object
            result = yaml.safe_load(result_str)
            
            # Ensure projectId is an integer
            if 'meta' in result and 'projectId' in result['meta']:
                try:
                    result['meta']['projectId'] = int(result['meta']['projectId'])
                except (ValueError, TypeError):
                    print(f"Warning: Could not convert projectId '{result['meta']['projectId']}' to integer")
            
            return result
        except Exception as e:
            print(f"Error replacing template variables: {e}")
            return None

    def get_token(self):
        reqUrl = RUN_AI_TOKEN_API
        headersList = {
            "Accept": "*/*",
            "Content-Type": "application/json"
        }
        payload = json.dumps({
            "grantType":"app_token",
            "AppId": self.app_client_id,
            "AppSecret" : self.app_client_secret
        })
        response = requests.request("POST", reqUrl, data=payload,  headers=headersList) 
        self.token="Bearer "+ response.json()["accessToken"]
        return(True)
    
    def validate_token(self):
        """Test the token by making a call to the tenants API"""
        reqUrl = f"{RUN_AI_BASE_URL}/api/v1/tenants"
        headersList = {
            "Accept": "*/*",
            "Content-Type": "application/json",
            "Authorization": self.token
        }
        
        try:
            response = requests.request("GET", reqUrl, headers=headersList)
            if response.status_code == 200:
                print("Token validation successful - proceeding with script execution")
                return True
            else:
                print(f"Token validation failed - Status code: {response.status_code}")
                print(f"Response: {response.text}")
                return False
        except Exception as e:
            print(f"Error validating token: {e}")
            return False
    
    def put_policy(self, type_policy, project_id, project_name, user_home_dir):
        headersList = {
            "Accept": "application/json, text/plain, */*",
            "Accept-Language": "en-US,en;q=0.9",
            "Content-Type": "application/json",
            "Authorization": self.token
        }
        
        # Convert project_id to integer if it's a string
        try:
            project_id_int = int(project_id)
        except ValueError:
            print(f"Warning: project_id '{project_id}' is not a valid integer, using as string")
            project_id_int = project_id
        
        # Prepare variables for template substitution
        variables = {
            'project_id': project_id_int,
            'project_name': project_name,
            'user_home_dir': user_home_dir,
            'type_policy': type_policy
        }
        
        # Select appropriate template
        if type_policy == "distributed":
            if 'distributed' not in self.templates:
                print(f"Error: Distributed template not available for {type_policy} policy")
                return False
            template = self.templates['distributed']
        else:
            if 'standard' not in self.templates:
                print(f"Error: Standard template not available for {type_policy} policy")
                return False
            template = self.templates['standard']
        
        # Replace template variables
        payload = self.replace_template_variables(template, variables)
        if payload is None:
            print(f"Error: Failed to process template for {type_policy} policy")
            return False

        # Step 1: Validate the policy first
        print(f"Validating {type_policy} policy for project {project_name}...")
        validateUrl = f"{RUN_AI_POLICY_API}/{type_policy}?validateOnly=true"
        validateResponse = requests.request("PUT", validateUrl, headers=headersList, json=payload)
        
        if validateResponse.status_code not in [200, 204]:
            print(f"Validation failed for {type_policy} policy - Project: {project_name}")
            print(f"Status Code: {validateResponse.status_code}")
            print(f"Response: {validateResponse.text}")
            return False
        
        print(f"Validation successful for {type_policy} policy - Project: {project_name}")
        
        # Step 2: Apply the policy if validation succeeds
        print(f"Applying {type_policy} policy for project {project_name}...")
        applyUrl = f"{RUN_AI_POLICY_API}/{type_policy}?validateOnly=false"
        applyResponse = requests.request("PUT", applyUrl, headers=headersList, json=payload)
        
        if applyResponse.status_code == 200:
            print(f"Policy applied successfully for {type_policy} - Project: {project_name}")
        else:
            print(f"Failed to apply {type_policy} policy - Project: {project_name}")
            print(f"Status Code: {applyResponse.status_code}")
            print(f"Response: {applyResponse.text}")
            return False
        
        print(applyResponse.text)
        return True
        
    def process_csv(self):
        with open(self.csv_file, newline='') as f:
            reader = csv.reader(f)
            next(reader)  # Skip header
            for i, data in enumerate(reader, start=2):  # Start=2 to match line number
                self.put_policy("trainings", data[0], data[1], data[2])
                self.put_policy("workspaces", data[0], data[1], data[2])
                self.put_policy("distributed", data[0], data[1], data[2])
                self.put_policy("inferences", data[0], data[1], data[2])

if __name__=="__main__":
    test = APIPolicyRequest()
    
    # Get token
    print("Getting authentication token...")
    if not test.get_token():
        print("Failed to get token. Exiting.")
        sys.exit(1)
    
    # Validate token
    print("Validating token...")
    if not test.validate_token():
        print("Token validation failed. Exiting.")
        sys.exit(1)
    
    # Process CSV
    print("Processing CSV file...")
    test.process_csv()