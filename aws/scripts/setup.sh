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

if ! command -v aws &> /dev/null; then
    echo -e "${RED}Error: AWS CLI not found.${NC}"
    echo "Install: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
    exit 1
fi
echo -e "  ${GREEN}✓${NC} AWS CLI found"

if ! aws sts get-caller-identity &> /dev/null; then
    echo -e "${YELLOW}Not logged in to AWS. Running 'aws configure'...${NC}"
    aws configure
fi
ACCOUNT_ID=$(aws sts get-caller-identity --query Account -o text)
REGION=$(aws configure get region)
if [ -z "$REGION" ]; then
    REGION="us-east-1"
fi
echo -e "  ${GREEN}✓${NC} Logged in: $ACCOUNT_ID ($REGION)"

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
echo -e "${YELLOW}This lab deploys AWS resources that cost ~\$3-5/session.${NC}"
echo -e "${YELLOW}Account: $ACCOUNT_ID ($REGION)${NC}"
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
echo "  1. Fix INC-001 (Dockerfile):  aws/docker/Dockerfile"
echo "  2. Fix INC-002 (Compose):     aws/docker/docker-compose.yml"
echo "  3. Fix INC-003 (CI):          aws/github-actions/ci.yml"
echo "  4. Fix INC-004 (Terraform):   aws/terraform/main.tf"
echo ""
echo "Once INC-004 is fixed, deploy infrastructure:"
echo "  cd aws/terraform"
echo "  terraform init"
echo "  terraform plan -var region=\"$REGION\""
echo "  terraform apply -var region=\"$REGION\""
echo ""
echo "Then continue with INC-005 through INC-007."
echo ""
echo "Validate progress:  ./validate.sh"
echo "Destroy resources:  ./destroy.sh"
echo ""
