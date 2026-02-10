#!/bin/bash
# =============================================================================
# DEVOPS LAB - DESTROY SCRIPT
# Tears down all Azure resources
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="${SCRIPT_DIR}/../terraform"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo ""
echo -e "${RED}============================================${NC}"
echo -e "${RED}   DEVOPS LAB - DESTROY RESOURCES${NC}"
echo -e "${RED}============================================${NC}"
echo ""

# Try terraform destroy first
if [ -f "${TERRAFORM_DIR}/terraform.tfstate" ]; then
    echo "Found Terraform state. Attempting terraform destroy..."
    
    RESOURCE_GROUP=$(cd "$TERRAFORM_DIR" && terraform output -raw resource_group_name 2>/dev/null || echo "")
    
    if [ -n "$RESOURCE_GROUP" ]; then
        echo -e "${YELLOW}Deleting resource group: $RESOURCE_GROUP${NC}"
        echo "This will destroy ALL resources in the group."
        echo ""
        read -p "Continue? (y/N) " -n 1 -r
        echo ""
        
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "Aborted."
            exit 0
        fi
        
        az group delete -n "$RESOURCE_GROUP" --yes --no-wait
        echo -e "${GREEN}Resource group deletion initiated.${NC}"
        echo "It may take a few minutes for all resources to be removed."
    fi
    
    # Clean up terraform state
    cd "$TERRAFORM_DIR"
    rm -f terraform.tfstate terraform.tfstate.backup
    rm -rf .terraform .terraform.lock.hcl
    echo -e "${GREEN}Terraform state cleaned up.${NC}"
else
    echo "No Terraform state found."
    echo ""
    echo "To manually check for resources:"
    echo "  az group list --query \"[?starts_with(name, 'rg-devopslab')]\" -o table"
    echo ""
    echo "To manually delete:"
    echo "  az group delete -n <resource-group-name> --yes"
fi

echo ""
echo -e "${GREEN}Cleanup complete.${NC}"
echo ""
