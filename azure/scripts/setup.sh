#!/bin/bash
# =============================================================================
# DEVOPS LAB - SETUP SCRIPT
# Initializes the lab and optionally deploys infrastructure
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="${SCRIPT_DIR}/../terraform"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo ""
echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}   DEVOPS LAB - SETUP${NC}"
echo -e "${BLUE}============================================${NC}"
echo ""

# Pre-flight checks
echo "Checking prerequisites..."

if ! command -v az &> /dev/null; then
    echo -e "${RED}Error: Azure CLI not found.${NC}"
    echo "Install: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
    exit 1
fi
echo -e "  ${GREEN}✓${NC} Azure CLI found"

if ! az account show &> /dev/null; then
    echo -e "${YELLOW}Not logged in to Azure. Running 'az login'...${NC}"
    az login
fi
ACCOUNT=$(az account show --query name -o tsv)
SUB_ID=$(az account show --query id -o tsv)
echo -e "  ${GREEN}✓${NC} Logged in: $ACCOUNT"

if ! command -v terraform &> /dev/null; then
    echo -e "${RED}Error: Terraform not found.${NC}"
    echo "Install: https://www.terraform.io/downloads"
    exit 1
fi
echo -e "  ${GREEN}✓${NC} Terraform found"

if ! command -v docker &> /dev/null; then
    echo -e "${YELLOW}Warning: Docker not found. You'll need it for INC-001 and INC-002.${NC}"
else
    echo -e "  ${GREEN}✓${NC} Docker found"
fi

if ! command -v kubectl &> /dev/null; then
    echo -e "${YELLOW}Warning: kubectl not found. You'll need it for INC-006.${NC}"
else
    echo -e "  ${GREEN}✓${NC} kubectl found"
fi

echo ""
echo -e "${YELLOW}This lab deploys Azure resources that cost ~\$3-5/session.${NC}"
echo -e "${YELLOW}Subscription: $ACCOUNT ($SUB_ID)${NC}"
echo ""
read -p "Continue? (y/N) " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
fi

echo ""
echo "Note: Before deploying, you need to fix the Terraform configuration (INC-004)."
echo "The Terraform files have intentional errors that must be fixed first."
echo ""
echo "To start working on the lab:"
echo "  1. Fix INC-001 (Dockerfile):  azure/docker/Dockerfile"
echo "  2. Fix INC-002 (Compose):     azure/docker/docker-compose.yml"
echo "  3. Fix INC-003 (CI):          azure/github-actions/ci.yml"
echo "  4. Fix INC-004 (Terraform):   azure/terraform/main.tf"
echo ""
echo "Once INC-004 is fixed, deploy infrastructure:"
echo "  cd azure/terraform"
echo "  terraform init"
echo "  terraform plan -var subscription_id=\"$SUB_ID\""
echo "  terraform apply -var subscription_id=\"$SUB_ID\""
echo ""
echo "Then continue with INC-005 through INC-007."
echo ""
echo "Validate progress:  ./validate.sh"
echo "Destroy resources:  ./destroy.sh"
echo ""
