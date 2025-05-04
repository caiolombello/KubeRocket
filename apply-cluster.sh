#!/usr/bin/env bash
set -euo pipefail

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Stage 1: Deploying base infrastructure and control plane${NC}"
terraform apply \
    -target=aws_key_pair.kubernetes \
    -target=aws_secretsmanager_secret.cluster_info \
    -target=aws_secretsmanager_secret.ssh_key \
    -target=module.vpc \
    -target=aws_security_group.control_plane \
    -target=aws_security_group.worker \
    -target=module.control_plane -auto-approve

echo -e "\n${YELLOW}Waiting for control plane to initialize...${NC}"
echo "This may take a few minutes. Checking secret status every 10 seconds..."

# Get the secret ARN from terraform output
secret_arn=$(terraform output -raw cluster_info_secret_arn)

# Function to check secret status
check_secret_status() {
    aws --profile=pvd --region=us-east-1 secretsmanager get-secret-value \
        --secret-id "$secret_arn" \
        --query 'SecretString' \
        --output text | \
        jq -r '.status' 2>/dev/null || echo "pending"
}

# Wait for secret to be ready
status="pending"
while [ "$status" != "ready" ]; do
    echo -n "."
    sleep 10
    status=$(check_secret_status)
done

echo -e "\n${GREEN}Control plane is ready!${NC}"

echo -e "\n${YELLOW}Stage 2: Deploying worker nodes and completing cluster setup${NC}"
terraform apply

echo -e "\n${GREEN}Cluster deployment completed!${NC}"
echo "You can now use kubectl with the following kubeconfig:"
echo "terraform output -raw kubeconfig | base64 -d > kubeconfig.yaml" 