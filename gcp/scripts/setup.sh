#!/bin/bash
# =============================================================================
# DEVOPS LAB - SETUP SCRIPT
# Initializes the lab and optionally deploys infrastructure
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo ""
echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}   DEVOPS LAB - GCP SETUP${NC}"
echo -e "${BLUE}============================================${NC}"
echo ""

echo "Checking prerequisites..."

if ! command -v gcloud &> /dev/null; then
    echo -e "${RED}Error: Google Cloud CLI not found.${NC}"
    echo "Install: https://cloud.google.com/sdk/docs/install"
    exit 1
fi
echo -e "  ${GREEN}✓${NC} Google Cloud CLI found"

if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
    echo -e "${YELLOW}Not logged in to Google Cloud. Running 'gcloud auth login'...${NC}"
    gcloud auth login
fi

if ! gcloud auth application-default print-access-token > /dev/null 2>&1; then
    echo -e "${YELLOW}Application default credentials not configured. Running 'gcloud auth application-default login'...${NC}"
    gcloud auth application-default login
fi

ACCOUNT=$(gcloud auth list --filter=status:ACTIVE --format="value(account)" | head -1)
PROJECT_ID=$(gcloud config get-value project 2>/dev/null || true)

echo -e "  ${GREEN}✓${NC} Logged in: $ACCOUNT"
if [ -n "$PROJECT_ID" ]; then
    echo -e "  ${GREEN}✓${NC} Active project: $PROJECT_ID"
else
    echo -e "${YELLOW}No active gcloud project set.${NC}"
    echo "Set one with: gcloud config set project <PROJECT_ID>"
fi

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
echo -e "${YELLOW}This lab deploys GCP resources that cost ~\$3-5/session.${NC}"
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
echo "  1. Fix INC-001 (Dockerfile):  gcp/docker/Dockerfile"
echo "  2. Fix INC-002 (Compose):     gcp/docker/docker-compose.yml"
echo "  3. Fix INC-003 (CI):          gcp/github-actions/ci.yml"
echo "  4. Fix INC-004 (Terraform):   gcp/terraform/main.tf"
echo ""
echo "Once INC-004 is fixed, deploy infrastructure:"
echo "  cd gcp/terraform"
echo "  terraform init"
echo "  terraform plan -var project_id=\"<your-project-id>\""
echo "  terraform apply -var project_id=\"<your-project-id>\""
echo ""
echo "Then continue with INC-005 through INC-007."
echo ""
echo "Validate progress:  ./validate.sh"
echo "Destroy resources:  ./destroy.sh"
echo ""
