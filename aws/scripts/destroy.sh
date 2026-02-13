#!/bin/bash
# =============================================================================
# DEVOPS LAB - DESTROY SCRIPT
# Tears down all AWS resources
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="${SCRIPT_DIR}/../terraform"

AUTO_APPROVE=false
for arg in "$@"; do
    case "$arg" in
        --yes|--auto-approve) AUTO_APPROVE=true ;;
    esac
done

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo ""
echo -e "${RED}============================================${NC}"
echo -e "${RED}   DEVOPS LAB - DESTROY RESOURCES${NC}"
echo -e "${RED}============================================${NC}"
echo ""

REGION=$(aws configure get region 2>/dev/null || echo "")
if [ -z "$REGION" ]; then
    REGION="us-east-1"
fi

empty_ecr_repository() {
    local REPO="$1"
    local IMAGE_IDS BATCHES
    IMAGE_IDS=$(aws ecr list-images --repository-name "$REPO" \
        --query 'imageIds' --output json 2>/dev/null || echo "[]")
    if [ -z "$IMAGE_IDS" ] || [ "$IMAGE_IDS" = "[]" ]; then
        return
    fi

    BATCHES=$(printf '%s' "$IMAGE_IDS" | python3 - <<'PY'
import json
import sys
try:
    data = json.load(sys.stdin)
except json.JSONDecodeError:
    sys.exit(0)
if not data:
    sys.exit(0)
for i in range(0, len(data), 100):
    print(json.dumps(data[i:i+100]))
PY
)
    while IFS= read -r batch; do
        [ -z "$batch" ] && continue
        aws ecr batch-delete-image --repository-name "$REPO" \
            --image-ids "$batch" >/dev/null 2>&1 || true
    done <<< "$BATCHES"
}

delete_elbs_for_vpc() {
    local VPC_ID="$1"
    local ELB_NAMES ELB_ARNS

    ELB_NAMES=$(aws elb describe-load-balancers \
        --query "LoadBalancerDescriptions[?VPCId=='$VPC_ID'].LoadBalancerName" \
        --output text 2>/dev/null || echo "")
    for name in $ELB_NAMES; do
        aws elb delete-load-balancer --load-balancer-name "$name" >/dev/null 2>&1 || true
    done

    ELB_ARNS=$(aws elbv2 describe-load-balancers \
        --query "LoadBalancers[?VpcId=='$VPC_ID'].LoadBalancerArn" \
        --output text 2>/dev/null || echo "")
    for arn in $ELB_ARNS; do
        aws elbv2 delete-load-balancer --load-balancer-arn "$arn" >/dev/null 2>&1 || true
    done
}

wait_for_elb_enis_gone() {
    local VPC_ID="$1"
    local REPEAT=20

    while [ $REPEAT -gt 0 ]; do
        local ENI_COUNT
        ENI_COUNT=$(aws ec2 describe-network-interfaces \
            --filters Name=vpc-id,Values="$VPC_ID" Name=description,Values="ELB*" \
            --query 'length(NetworkInterfaces)' --output text 2>/dev/null || echo "0")
        if [ "$ENI_COUNT" = "0" ]; then
            return
        fi
        sleep 10
        REPEAT=$((REPEAT - 1))
    done
}

unmap_public_addresses() {
    local VPC_ID="$1"
    local ENIS

    ENIS=$(aws ec2 describe-network-interfaces \
        --filters Name=vpc-id,Values="$VPC_ID" \
        --query 'NetworkInterfaces[].NetworkInterfaceId' --output text 2>/dev/null || echo "")
    for eni in $ENIS; do
        local ASSOC_ID ALLOC_ID
        ASSOC_ID=$(aws ec2 describe-addresses \
            --filters Name=network-interface-id,Values="$eni" \
            --query 'Addresses[].AssociationId' --output text 2>/dev/null || echo "")
        for assoc in $ASSOC_ID; do
            aws ec2 disassociate-address --association-id "$assoc" >/dev/null 2>&1 || true
        done

        ALLOC_ID=$(aws ec2 describe-addresses \
            --filters Name=network-interface-id,Values="$eni" \
            --query 'Addresses[].AllocationId' --output text 2>/dev/null || echo "")
        for alloc in $ALLOC_ID; do
            aws ec2 release-address --allocation-id "$alloc" >/dev/null 2>&1 || true
        done
    done
}

delete_available_enis() {
    local VPC_ID="$1"
    local ENIS

    ENIS=$(aws ec2 describe-network-interfaces \
        --filters Name=vpc-id,Values="$VPC_ID" \
        --query 'NetworkInterfaces[?Status==`available`].NetworkInterfaceId' \
        --output text 2>/dev/null || echo "")
    for eni in $ENIS; do
        aws ec2 delete-network-interface --network-interface-id "$eni" >/dev/null 2>&1 || true
    done
}

delete_security_groups_for_vpc() {
    local VPC_ID="$1"
    local SG_GROUPS

    SG_GROUPS=$(aws ec2 describe-security-groups \
        --filters Name=vpc-id,Values="$VPC_ID" \
        --query 'SecurityGroups[?GroupName!=`default`].GroupId' --output text 2>/dev/null || echo "")
    for sg in $SG_GROUPS; do
        aws ec2 delete-security-group --group-id "$sg" >/dev/null 2>&1 || true
    done
}

if [ -f "${TERRAFORM_DIR}/terraform.tfstate" ]; then
    echo "Found Terraform state. Attempting terraform destroy..."

    echo -e "${YELLOW}This will destroy ALL resources in the Terraform state.${NC}"
    echo ""
    if [ "$AUTO_APPROVE" = false ]; then
        read -p "Continue? (y/N) " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "Aborted."
            exit 0
        fi
    fi

    cd "$TERRAFORM_DIR"
    ECR_REPO=$(terraform output -raw ecr_repository_name 2>/dev/null || echo "")
    EKS_NAME=$(terraform output -raw eks_cluster_name 2>/dev/null || echo "")
    VPC_ID=$(terraform output -raw vpc_id 2>/dev/null || echo "")
    if [ -n "$ECR_REPO" ]; then
        empty_ecr_repository "$ECR_REPO"
    fi

    if [ -n "$EKS_NAME" ]; then
        echo "Cleaning Kubernetes load balancers..."
        aws eks update-kubeconfig --region "$REGION" --name "$EKS_NAME" >/dev/null 2>&1 || true
        kubectl delete svc devops-lab-app -n devops-lab >/dev/null 2>&1 || true
        kubectl delete namespace devops-lab >/dev/null 2>&1 || true
    fi

    if [ -n "$VPC_ID" ]; then
        echo "Releasing public addresses and load balancers..."
        delete_elbs_for_vpc "$VPC_ID"
        wait_for_elb_enis_gone "$VPC_ID"
        unmap_public_addresses "$VPC_ID"
        delete_available_enis "$VPC_ID"
        delete_security_groups_for_vpc "$VPC_ID"
    fi

    echo "Preparing EKS resources for destroy..."
    terraform destroy -auto-approve -var region="$REGION" -target=aws_eks_node_group.main >/dev/null 2>&1 || true
    terraform destroy -auto-approve -var region="$REGION" -target=aws_eks_cluster.main >/dev/null 2>&1 || true

    set +e
    terraform destroy -auto-approve -var region="$REGION"
    TF_DESTROY_EXIT=$?
    set -e

    if [ $TF_DESTROY_EXIT -eq 0 ]; then
        rm -f terraform.tfstate terraform.tfstate.backup
        rm -rf .terraform .terraform.lock.hcl
        echo -e "${GREEN}Terraform state cleaned up.${NC}"
    else
        echo -e "${YELLOW}Terraform destroy failed.${NC}"
    fi
else
    echo "No Terraform state found."
fi
