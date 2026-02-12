#!/usr/bin/env bash
# =============================================================================
# DEVOPS LAB - FULL END-TO-END VALIDATION
# Applies fixes, deploys to AWS, validates, generates token, destroys
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${SCRIPT_DIR}/../../../../.."
AWS_DIR="${REPO_ROOT}/aws"
TERRAFORM_DIR="${AWS_DIR}/terraform"
VALIDATE_SCRIPT="${AWS_DIR}/scripts/validate.sh"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

SKIP_DEPLOY=false
SKIP_DESTROY=false
for arg in "$@"; do
    case "$arg" in
        --skip-deploy) SKIP_DEPLOY=true ;;
        --skip-destroy) SKIP_DESTROY=true ;;
    esac
done

TOTAL_STEPS=9
PASSED=0
FAILED=0
RESULTS=()
CLEANUP_RAN=false

log_result() {
    local STEP="$1"
    local STATUS="$2"
    if [ "$STATUS" = "PASS" ]; then
        RESULTS+=("PASS:$STEP")
        PASSED=$((PASSED + 1))
    else
        RESULTS+=("FAIL:$STEP")
        FAILED=$((FAILED + 1))
    fi
}

cleanup() {
  if [ "$CLEANUP_RAN" = true ]; then
    return
  fi
  CLEANUP_RAN=true

  echo ""
  echo -e "${YELLOW}Cleaning up...${NC}"

  if [ "$SKIP_DESTROY" = false ]; then
    "${AWS_DIR}/scripts/destroy.sh"
  else
    echo -e "  ${YELLOW}SKIPPED (--skip-destroy)${NC}"
  fi
}

trap cleanup EXIT

echo ""
echo "=============================================================="
echo " DEVOPS LAB - FULL VALIDATION"
echo "=============================================================="
echo ""

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null)
AWS_REGION=$(aws configure get region 2>/dev/null)
if [ -z "$AWS_REGION" ]; then
    AWS_REGION="us-east-1"
fi
echo "AWS Account: $ACCOUNT_ID"
echo "Region: $AWS_REGION"
echo ""

# -----------------------------------------------------------------
# Step 1: Fix INC-001 (Dockerfile)
# -----------------------------------------------------------------
echo -e "${CYAN}[1/$TOTAL_STEPS] Fixing INC-001 (Dockerfile)...${NC}"

cat > "${AWS_DIR}/docker/Dockerfile" << 'EOF'
FROM python:3.11-slim
WORKDIR /app
COPY app/requirements.txt .
RUN pip install -r requirements.txt
COPY app/ .
EXPOSE 8000
CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8000"]
EOF

if docker build -f "${AWS_DIR}/docker/Dockerfile" -t devops-lab-test "${AWS_DIR}" > /dev/null 2>&1; then
    CID=$(docker run -d -p 18000:8000 -e REDIS_HOST=localhost devops-lab-test 2>/dev/null || echo "")
    sleep 3
    RESP=$(curl -s --max-time 5 http://localhost:18000/health 2>/dev/null || echo "")
    docker rm -f "$CID" > /dev/null 2>&1 || true
    docker rmi devops-lab-test > /dev/null 2>&1 || true
    if echo "$RESP" | grep -q "healthy"; then
        echo -e "  ${GREEN}PASS${NC}"
        log_result "Fix INC-001 (Dockerfile)" "PASS"
    else
        echo -e "  ${RED}FAIL - Container didn't respond${NC}"
        log_result "Fix INC-001 (Dockerfile)" "FAIL"
    fi
else
    echo -e "  ${RED}FAIL - Build failed${NC}"
    log_result "Fix INC-001 (Dockerfile)" "FAIL"
fi

# -----------------------------------------------------------------
# Step 2: Fix INC-002 (Docker Compose)
# -----------------------------------------------------------------
echo -e "${CYAN}[2/$TOTAL_STEPS] Fixing INC-002 (Docker Compose)...${NC}"

cat > "${AWS_DIR}/docker/docker-compose.yml" << 'EOF'
services:
  app:
    build:
      context: ..
      dockerfile: docker/Dockerfile
    ports:
      - "8000:8000"
    environment:
      - REDIS_HOST=redis
      - REDIS_PORT=6379
    depends_on:
      - redis
    networks:
      - backend

  redis:
    image: redis:alpine
    ports:
      - "6379:6379"
    volumes:
      - redis_data:/data
    networks:
      - backend

networks:
  backend:

volumes:
  redis_data:
EOF

docker compose -f "${AWS_DIR}/docker/docker-compose.yml" up -d --build > /dev/null 2>&1 || true
sleep 5
RESP=$(curl -s --max-time 5 http://localhost:8000/health 2>/dev/null || echo "")
docker compose -f "${AWS_DIR}/docker/docker-compose.yml" down > /dev/null 2>&1 || true

if echo "$RESP" | grep -q '"redis":"connected"'; then
    echo -e "  ${GREEN}PASS${NC}"
    log_result "Fix INC-002 (Docker Compose)" "PASS"
else
    echo -e "  ${RED}FAIL - Services didn't communicate${NC}"
    log_result "Fix INC-002 (Docker Compose)" "FAIL"
fi

# -----------------------------------------------------------------
# Step 3: Fix INC-003 (CI Pipeline)
# -----------------------------------------------------------------
echo -e "${CYAN}[3/$TOTAL_STEPS] Fixing INC-003 (CI Pipeline)...${NC}"

cat > "${AWS_DIR}/github-actions/ci.yml" << 'EOF'
name: CI Pipeline

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  build-and-test:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Set up Python
        uses: actions/setup-python@v5
        with:
          python-version: "3.11"

      - name: Install dependencies
        working-directory: ./aws/app
        run: |
          pip install -r requirements.txt

      - name: Run tests
        working-directory: ./aws/app
        run: |
          python -m pytest tests/ -v

      - name: Build Docker image
        run: |
          docker build -f aws/docker/Dockerfile -t devops-lab-app .
EOF

if python3 -c "import yaml; yaml.safe_load(open('${AWS_DIR}/github-actions/ci.yml'))" 2>/dev/null; then
    echo -e "  ${GREEN}PASS${NC}"
    log_result "Fix INC-003 (CI Pipeline)" "PASS"
else
    echo -e "  ${RED}FAIL - YAML invalid${NC}"
    log_result "Fix INC-003 (CI Pipeline)" "FAIL"
fi

# -----------------------------------------------------------------
# Step 4: Fix INC-004 (Terraform) + Deploy
# -----------------------------------------------------------------
echo -e "${CYAN}[4/$TOTAL_STEPS] Fixing INC-004 (Terraform) + Deploy...${NC}"

cat > "${AWS_DIR}/terraform/main.tf" << 'TFEOF'
terraform {
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  region = var.region
}

resource "random_id" "deployment" {
  byte_length = 4
}

resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name = "vpc-devopslab-${random_id.deployment.hex}"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name = "igw-devopslab-${random_id.deployment.hex}"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "rtb-devopslab-${random_id.deployment.hex}"
  }
}

resource "aws_subnet" "eks_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "${var.region}a"
  map_public_ip_on_launch = true
  tags = {
    Name = "snet-eks-a"
  }
}

resource "aws_subnet" "eks_b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "${var.region}b"
  map_public_ip_on_launch = true
  tags = {
    Name = "snet-eks-b"
  }
}

resource "aws_route_table_association" "eks_a" {
  subnet_id      = aws_subnet.eks_a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "eks_b" {
  subnet_id      = aws_subnet.eks_b.id
  route_table_id = aws_route_table.public.id
}

resource "aws_ecr_repository" "main" {
  name = "devopslab-${random_id.deployment.hex}"
  force_delete = true
}

resource "aws_cloudwatch_log_group" "eks" {
  name              = "/aws/eks/devopslab-${random_id.deployment.hex}"
  retention_in_days = 30
}

resource "aws_iam_role" "eks_cluster" {
  name = "eks-cluster-role-${random_id.deployment.hex}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  role       = aws_iam_role.eks_cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_iam_role" "eks_node" {
  name = "eks-node-role-${random_id.deployment.hex}"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "eks_node_policy" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "eks_cni_policy" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "eks_ecr_policy" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_eks_cluster" "main" {
  name     = "eks-devopslab-${random_id.deployment.hex}"
  role_arn = aws_iam_role.eks_cluster.arn

  vpc_config {
    subnet_ids = [aws_subnet.eks_a.id, aws_subnet.eks_b.id]
  }

  kubernetes_network_config {
    service_ipv4_cidr = "172.20.0.0/16"
  }
}

resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "ng-devopslab-${random_id.deployment.hex}"
  node_role_arn   = aws_iam_role.eks_node.arn
  subnet_ids      = [aws_subnet.eks_a.id, aws_subnet.eks_b.id]

  scaling_config {
    desired_size = 1
    max_size     = 1
    min_size     = 1
  }

  instance_types = ["t3.medium"]

  depends_on = [
    aws_iam_role_policy_attachment.eks_node_policy,
    aws_iam_role_policy_attachment.eks_cni_policy,
    aws_iam_role_policy_attachment.eks_ecr_policy
  ]
}
TFEOF

cat > "${AWS_DIR}/terraform/outputs.tf" << 'EOF'
output "vpc_id" {
  value = aws_vpc.main.id
}

output "ecr_repository_url" {
  value = aws_ecr_repository.main.repository_url
}

output "ecr_repository_name" {
  value = aws_ecr_repository.main.name
}

output "eks_cluster_name" {
  value = aws_eks_cluster.main.name
}

output "deployment_id" {
  value = random_id.deployment.hex
}

output "log_group_name" {
  value = aws_cloudwatch_log_group.eks.name
}
EOF

if [ "$SKIP_DEPLOY" = false ]; then
    cd "$TERRAFORM_DIR"
    terraform init > /dev/null 2>&1
    if terraform validate > /dev/null 2>&1; then
        echo "  Deploying to AWS (this takes ~10-15 minutes)..."
        if terraform apply -auto-approve -var region="$AWS_REGION" > /tmp/tf-apply.log 2>&1; then
            echo -e "  ${GREEN}PASS${NC}"
            log_result "Fix INC-004 (Terraform Deploy)" "PASS"
        else
            echo -e "  ${RED}FAIL - terraform apply failed${NC}"
            tail -20 /tmp/tf-apply.log
            log_result "Fix INC-004 (Terraform Deploy)" "FAIL"
        fi
    else
        echo -e "  ${RED}FAIL - terraform validate failed${NC}"
        terraform validate
        log_result "Fix INC-004 (Terraform Deploy)" "FAIL"
    fi
    cd "$SCRIPT_DIR"
else
    echo -e "  ${YELLOW}SKIPPED (--skip-deploy)${NC}"
    log_result "Fix INC-004 (Terraform Deploy)" "PASS"
fi

# -----------------------------------------------------------------
# Step 5: Fix INC-005 (CD Pipeline)
# -----------------------------------------------------------------
echo -e "${CYAN}[5/$TOTAL_STEPS] Fixing INC-005 (CD Pipeline)...${NC}"

cat > "${AWS_DIR}/github-actions/cd.yml" << 'EOF'
name: CD Pipeline

on:
  workflow_dispatch:
  push:
    branches: [main]

env:
  AWS_REGION: ${{ secrets.AWS_REGION }}
  ECR_REPO: ${{ secrets.ECR_REPO }}
  EKS_CLUSTER: ${{ secrets.EKS_CLUSTER_NAME }}

jobs:
  build-and-push:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: ${{ env.AWS_REGION }}

      - name: Login to ECR
        run: |
          aws ecr get-login-password --region ${{ env.AWS_REGION }} | \
            docker login --username AWS --password-stdin ${{ env.ECR_REPO }}

      - name: Build and push image
        run: |
          docker build -f aws/docker/Dockerfile -t ${{ env.ECR_REPO }}:latest .
          docker push ${{ env.ECR_REPO }}:latest

  deploy-to-eks:
    runs-on: ubuntu-latest
    needs: build-and-push
    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: ${{ env.AWS_REGION }}

      - name: Get EKS credentials
        run: |
          aws eks update-kubeconfig --region ${{ env.AWS_REGION }} --name ${{ env.EKS_CLUSTER }}

      - name: Deploy to EKS
        run: |
          kubectl set image deployment/devops-lab-app app=${{ env.ECR_REPO }}:latest -n devops-lab
EOF

if ! grep -q "credentials:" "${AWS_DIR}/github-actions/cd.yml" && grep -q "aws-access-key-id" "${AWS_DIR}/github-actions/cd.yml"; then
    echo -e "  ${GREEN}PASS${NC}"
    log_result "Fix INC-005 (CD Pipeline)" "PASS"
else
    echo -e "  ${RED}FAIL${NC}"
    log_result "Fix INC-005 (CD Pipeline)" "FAIL"
fi

# -----------------------------------------------------------------
# Step 6: Fix INC-006 (Kubernetes) + Deploy to EKS
# -----------------------------------------------------------------
echo -e "${CYAN}[6/$TOTAL_STEPS] Fixing INC-006 (Kubernetes) + Deploy...${NC}"

if [ "$SKIP_DEPLOY" = false ] && [ -f "${TERRAFORM_DIR}/terraform.tfstate" ]; then
    cd "$TERRAFORM_DIR"
    ECR_URL=$(terraform output -raw ecr_repository_url 2>/dev/null)
    EKS_NAME=$(terraform output -raw eks_cluster_name 2>/dev/null)
    cd "$SCRIPT_DIR"

    echo "  Pushing image to ECR..."
    aws ecr get-login-password --region "$AWS_REGION" | \
        docker login --username AWS --password-stdin "$ECR_URL" > /dev/null 2>&1
    docker buildx build --platform linux/amd64 -f "${AWS_DIR}/docker/Dockerfile" \
        -t "${ECR_URL}:latest" --push "${AWS_DIR}" > /dev/null 2>&1

    aws eks update-kubeconfig --region "$AWS_REGION" --name "$EKS_NAME" > /dev/null 2>&1
fi

ECR_URL_FOR_K8S="${ECR_URL:-ECR_REGISTRY}"

cat > "${AWS_DIR}/kubernetes/app-deployment.yaml" << EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: devops-lab-app
  namespace: devops-lab
spec:
  replicas: 2
  selector:
    matchLabels:
      app: devops-lab-app
  template:
    metadata:
      labels:
        app: devops-lab-app
    spec:
      containers:
        - name: app
          image: ${ECR_URL_FOR_K8S}:latest
          ports:
            - containerPort: 8000
          env:
            - name: REDIS_HOST
              value: "redis"
            - name: REDIS_PORT
              value: "6379"
          livenessProbe:
            httpGet:
              path: /health
              port: 8000
            initialDelaySeconds: 10
          readinessProbe:
            httpGet:
              path: /health
              port: 8000
            initialDelaySeconds: 5
EOF

cat > "${AWS_DIR}/kubernetes/app-service.yaml" << 'EOF'
apiVersion: v1
kind: Service
metadata:
  name: devops-lab-app
  namespace: devops-lab
spec:
  type: LoadBalancer
  selector:
    app: devops-lab-app
  ports:
    - protocol: TCP
      port: 80
      targetPort: 8000
EOF

cat > "${AWS_DIR}/kubernetes/redis-deployment.yaml" << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: redis
  namespace: devops-lab
spec:
  replicas: 1
  selector:
    matchLabels:
      app: redis
  template:
    metadata:
      labels:
        app: redis
    spec:
      containers:
        - name: redis
          image: redis:alpine
          ports:
            - containerPort: 6379
EOF

cat > "${AWS_DIR}/kubernetes/redis-service.yaml" << 'EOF'
apiVersion: v1
kind: Service
metadata:
  name: redis
  namespace: devops-lab
spec:
  selector:
    app: redis
  ports:
    - protocol: TCP
      port: 6379
      targetPort: 6379
EOF

if [ "$SKIP_DEPLOY" = false ] && [ -n "$EKS_NAME" ]; then
    echo "  Deploying to EKS..."
    kubectl apply -f "${AWS_DIR}/kubernetes/namespace.yaml" > /dev/null 2>&1
    kubectl apply -f "${AWS_DIR}/kubernetes/" > /dev/null 2>&1

    echo "  Waiting for pods..."
    for i in $(seq 1 12); do
        sleep 10
        PODS_READY=$(kubectl get pods -n devops-lab --no-headers 2>/dev/null | grep -c "Running" || echo "0")
        if [ "$PODS_READY" -ge 3 ]; then
            break
        fi
        echo "    ($i/12) $PODS_READY pods running..."
    done
    if [ "$PODS_READY" -ge 3 ]; then
        echo -e "  ${GREEN}PASS ($PODS_READY pods running)${NC}"
        log_result "Fix INC-006 (Kubernetes)" "PASS"
    else
        echo -e "  ${RED}FAIL - Only $PODS_READY pods running${NC}"
        kubectl get pods -n devops-lab 2>/dev/null
        log_result "Fix INC-006 (Kubernetes)" "FAIL"
    fi
else
    if ! grep -q "v1beta1" "${AWS_DIR}/kubernetes/app-deployment.yaml" && \
       ! grep -q "ECR_REGISTRY" "${AWS_DIR}/kubernetes/app-deployment.yaml" && \
       ! grep -q "containerPort: 5000" "${AWS_DIR}/kubernetes/app-deployment.yaml"; then
        echo -e "  ${GREEN}PASS (local validation)${NC}"
        log_result "Fix INC-006 (Kubernetes)" "PASS"
    else
        echo -e "  ${RED}FAIL${NC}"
        log_result "Fix INC-006 (Kubernetes)" "FAIL"
    fi
fi

# -----------------------------------------------------------------
# Step 7: Fix INC-007 (Monitoring)
# -----------------------------------------------------------------
echo -e "${CYAN}[7/$TOTAL_STEPS] Fixing INC-007 (Monitoring)...${NC}"

cat > "${AWS_DIR}/monitoring/alerts.json" << 'EOF'
{
  "alarms": [
    {
      "AlarmName": "high-cpu-alarm",
      "Namespace": "ContainerInsights",
      "MetricName": "node_cpu_utilization",
      "Statistic": "Average",
      "Period": 60,
      "EvaluationPeriods": 5,
      "Threshold": 90,
      "ComparisonOperator": "GreaterThanThreshold",
      "ActionsEnabled": true,
      "Severity": 2
    },
    {
      "AlarmName": "pod-restart-alarm",
      "Namespace": "ContainerInsights",
      "MetricName": "pod_number_of_container_restarts",
      "Statistic": "Maximum",
      "Period": 60,
      "EvaluationPeriods": 1,
      "Threshold": 3,
      "ComparisonOperator": "GreaterThanThreshold",
      "ActionsEnabled": true,
      "Severity": 2
    }
  ]
}
EOF

ENABLED=$(python3 -c "
import json
with open('${AWS_DIR}/monitoring/alerts.json') as f:
    data = json.load(f)
for alarm in data.get('alarms', []):
    if alarm.get('AlarmName') == 'pod-restart-alarm':
        print(alarm.get('ActionsEnabled'))
" 2>/dev/null || echo "false")

if [ "$ENABLED" = "True" ]; then
    echo -e "  ${GREEN}PASS${NC}"
    log_result "Fix INC-007 (Monitoring)" "PASS"
else
    echo -e "  ${RED}FAIL${NC}"
    log_result "Fix INC-007 (Monitoring)" "FAIL"
fi

# -----------------------------------------------------------------
# Step 8: Token Generation
# -----------------------------------------------------------------
echo -e "${CYAN}[8/$TOTAL_STEPS] Testing token generation...${NC}"

TOKEN=$(echo "testuser" | "$VALIDATE_SCRIPT" export 2>/dev/null | grep -A1 "BEGIN L2C" | tail -1)

if [ -n "$TOKEN" ] && [ ${#TOKEN} -gt 20 ]; then
    echo -e "  ${GREEN}PASS${NC}"
    log_result "Token Generation" "PASS"
else
    echo -e "  ${RED}FAIL - No token generated${NC}"
    log_result "Token Generation" "FAIL"
fi

# -----------------------------------------------------------------
# Step 9: Token Verification
# -----------------------------------------------------------------
echo -e "${CYAN}[9/$TOTAL_STEPS] Testing token verification...${NC}"

if [ -n "$TOKEN" ]; then
    VERIFY_OUTPUT=$("$VALIDATE_SCRIPT" verify "$TOKEN" 2>&1)
    if echo "$VERIFY_OUTPUT" | grep -q "VALID"; then
        echo -e "  ${GREEN}PASS${NC}"
        log_result "Token Verification" "PASS"
    else
        echo -e "  ${RED}FAIL - Token verification failed${NC}"
        echo "$VERIFY_OUTPUT"
        log_result "Token Verification" "FAIL"
    fi
else
    echo -e "  ${RED}FAIL - No token to verify${NC}"
    log_result "Token Verification" "FAIL"
fi

  # -----------------------------------------------------------------
  # Cleanup: Destroy Resources
  # -----------------------------------------------------------------
  echo -e "${CYAN}[Cleanup] Destroying resources...${NC}"
  cleanup

# -----------------------------------------------------------------
# Summary
# -----------------------------------------------------------------
echo ""
echo "=============================================================="
echo " VALIDATION SUMMARY"
echo "=============================================================="
echo ""
echo "Step                               | Result"
echo "-----------------------------------+--------"

for entry in "${RESULTS[@]}"; do
    STATUS="${entry%%:*}"
    STEP="${entry#*:}"
    if [ "$STATUS" = "PASS" ]; then
        printf "%-34s | ${GREEN}PASS${NC}\n" "$STEP"
    else
        printf "%-34s | ${RED}FAIL${NC}\n" "$STEP"
    fi
done

echo ""

echo ""
if [ $FAILED -eq 0 ]; then
    echo "=============================================================="
    echo -e "  ${GREEN}ALL TESTS PASSED ($PASSED/$TOTAL_STEPS)${NC}"
    echo "  Lab validation complete - ready for student use"
    echo "=============================================================="
    exit 0
else
    echo "=============================================================="
    echo -e "  ${RED}SOME TESTS FAILED ($PASSED passed, $FAILED failed)${NC}"
    echo "=============================================================="
    exit 1
fi
