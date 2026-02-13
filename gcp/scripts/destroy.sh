#!/bin/bash
# =============================================================================
# DEVOPS LAB - DESTROY SCRIPT
# Tears down all GCP resources
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

if [ -f "${TERRAFORM_DIR}/terraform.tfstate" ]; then
    echo "Found Terraform state. Attempting terraform destroy..."
    echo "This will destroy ALL resources created by the lab."
    echo ""
    read -p "Continue? (y/N) " -n 1 -r
    echo ""

    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 0
    fi

    cd "$TERRAFORM_DIR"
    terraform destroy -auto-approve || true

    rm -f terraform.tfstate terraform.tfstate.backup
    rm -rf .terraform .terraform.lock.hcl
    echo -e "${GREEN}Terraform state cleaned up.${NC}"
else
    echo "No Terraform state found."
    echo ""
    echo "To manually check for resources:"
    echo "  gcloud container clusters list"
    echo "  gcloud artifacts repositories list --location <region>"
fi

echo ""
echo -e "${GREEN}Cleanup complete.${NC}"
echo ""
