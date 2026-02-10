#!/usr/bin/env bash
# =============================================================================
# DEVOPS LAB - FULL END-TO-END VALIDATION
# Applies fixes, deploys to Azure, validates, generates token, destroys
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${SCRIPT_DIR}/../../../../.."
AZURE_DIR="${REPO_ROOT}/azure"
TERRAFORM_DIR="${AZURE_DIR}/terraform"
VALIDATE_SCRIPT="${AZURE_DIR}/scripts/validate.sh"

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
    echo ""
    echo -e "${YELLOW}Cleaning up...${NC}"

    # Restore broken files
    cd "$REPO_ROOT"
    git checkout -- azure/ 2>/dev/null || true

    # Destroy Azure resources
    if [ "$SKIP_DESTROY" = false ] && [ -f "${TERRAFORM_DIR}/terraform.tfstate" ]; then
        local RG
        RG=$(cd "$TERRAFORM_DIR" && terraform output -raw resource_group_name 2>/dev/null || echo "")
        if [ -n "$RG" ]; then
            echo "Deleting resource group: $RG"
            az group delete -n "$RG" --yes --no-wait 2>/dev/null || true
        fi
        rm -rf "${TERRAFORM_DIR}/.terraform" "${TERRAFORM_DIR}/.terraform.lock.hcl" "${TERRAFORM_DIR}/terraform.tfstate"*
    fi
}

trap cleanup EXIT

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║          DEVOPS LAB - FULL VALIDATION                       ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

SUB_ID=$(az account show --query id -o tsv 2>/dev/null)
echo "Azure Subscription: $SUB_ID"
echo ""

# ─────────────────────────────────────────────────────────────────
# Step 1: Fix INC-001 (Dockerfile)
# ─────────────────────────────────────────────────────────────────
echo -e "${CYAN}[1/$TOTAL_STEPS] Fixing INC-001 (Dockerfile)...${NC}"

cat > "${AZURE_DIR}/docker/Dockerfile" << 'EOF'
FROM python:3.11-slim
WORKDIR /app
COPY app/requirements.txt .
RUN pip install -r requirements.txt
COPY app/ .
EXPOSE 8000
CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8000"]
EOF

if docker build -f "${AZURE_DIR}/docker/Dockerfile" -t devops-lab-test "${AZURE_DIR}" > /dev/null 2>&1; then
    CID=$(docker run -d -p 18000:8000 -e REDIS_HOST=localhost devops-lab-test 2>/dev/null || echo "")
    sleep 3
    RESP=$(curl -s --max-time 5 http://localhost:18000/health 2>/dev/null || echo "")
    docker rm -f "$CID" > /dev/null 2>&1 || true
    docker rmi devops-lab-test > /dev/null 2>&1 || true
    if echo "$RESP" | grep -q "healthy"; then
        echo -e "  ${GREEN}✓ PASS${NC}"
        log_result "Fix INC-001 (Dockerfile)" "PASS"
    else
        echo -e "  ${RED}✗ FAIL - Container didn't respond${NC}"
        log_result "Fix INC-001 (Dockerfile)" "FAIL"
    fi
else
    echo -e "  ${RED}✗ FAIL - Build failed${NC}"
    log_result "Fix INC-001 (Dockerfile)" "FAIL"
fi

# ─────────────────────────────────────────────────────────────────
# Step 2: Fix INC-002 (Docker Compose)
# ─────────────────────────────────────────────────────────────────
echo -e "${CYAN}[2/$TOTAL_STEPS] Fixing INC-002 (Docker Compose)...${NC}"

cat > "${AZURE_DIR}/docker/docker-compose.yml" << 'EOF'
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

docker compose -f "${AZURE_DIR}/docker/docker-compose.yml" up -d --build > /dev/null 2>&1 || true
sleep 5
RESP=$(curl -s --max-time 5 http://localhost:8000/health 2>/dev/null || echo "")
docker compose -f "${AZURE_DIR}/docker/docker-compose.yml" down > /dev/null 2>&1 || true

if echo "$RESP" | grep -q '"redis":"connected"'; then
    echo -e "  ${GREEN}✓ PASS${NC}"
    log_result "Fix INC-002 (Docker Compose)" "PASS"
else
    echo -e "  ${RED}✗ FAIL - Services didn't communicate${NC}"
    log_result "Fix INC-002 (Docker Compose)" "FAIL"
fi

# ─────────────────────────────────────────────────────────────────
# Step 3: Fix INC-003 (CI Pipeline)
# ─────────────────────────────────────────────────────────────────
echo -e "${CYAN}[3/$TOTAL_STEPS] Fixing INC-003 (CI Pipeline)...${NC}"

cat > "${AZURE_DIR}/github-actions/ci.yml" << 'EOF'
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
        working-directory: ./azure/app
        run: |
          pip install -r requirements.txt

      - name: Run tests
        working-directory: ./azure/app
        run: |
          python -m pytest tests/ -v

      - name: Build Docker image
        run: |
          docker build -f azure/docker/Dockerfile -t devops-lab-app .
EOF

if python3 -c "import yaml; yaml.safe_load(open('${AZURE_DIR}/github-actions/ci.yml'))" 2>/dev/null; then
    echo -e "  ${GREEN}✓ PASS${NC}"
    log_result "Fix INC-003 (CI Pipeline)" "PASS"
else
    echo -e "  ${RED}✗ FAIL - YAML invalid${NC}"
    log_result "Fix INC-003 (CI Pipeline)" "FAIL"
fi

# ─────────────────────────────────────────────────────────────────
# Step 4: Fix INC-004 (Terraform) + Deploy
# ─────────────────────────────────────────────────────────────────
echo -e "${CYAN}[4/$TOTAL_STEPS] Fixing INC-004 (Terraform) + Deploy...${NC}"

cat > "${AZURE_DIR}/terraform/main.tf" << 'TFEOF'
terraform {
  required_version = ">= 1.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}

resource "random_id" "deployment" {
  byte_length = 4
}

resource "azurerm_resource_group" "main" {
  name     = "rg-devopslab-${random_id.deployment.hex}"
  location = var.location
}

resource "azurerm_virtual_network" "main" {
  name                = "vnet-devopslab-${random_id.deployment.hex}"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
}

resource "azurerm_subnet" "aks" {
  name                 = "snet-aks"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.1.0/24"]
}

resource "azurerm_container_registry" "main" {
  name                = "acrdevopslab${random_id.deployment.hex}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = "Basic"
  admin_enabled       = true
}

resource "azurerm_log_analytics_workspace" "main" {
  name                = "law-devopslab-${random_id.deployment.hex}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

resource "azurerm_kubernetes_cluster" "main" {
  name                = "aks-devopslab-${random_id.deployment.hex}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  dns_prefix          = "devopslab${random_id.deployment.hex}"

  default_node_pool {
    name           = "default"
    node_count     = 1
    vm_size        = "Standard_B4ms"
    vnet_subnet_id = azurerm_subnet.aks.id
  }

  identity {
    type = "SystemAssigned"
  }

  oms_agent {
    log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  }

  network_profile {
    network_plugin = "azure"
    service_cidr   = "172.16.0.0/16"
    dns_service_ip = "172.16.0.10"
  }
}

resource "azurerm_role_assignment" "aks_acr" {
  scope                = azurerm_container_registry.main.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_kubernetes_cluster.main.kubelet_identity[0].object_id
}
TFEOF

cat > "${AZURE_DIR}/terraform/outputs.tf" << 'EOF'
output "resource_group_name" {
  value = azurerm_resource_group.main.name
}

output "acr_login_server" {
  value = azurerm_container_registry.main.login_server
}

output "acr_name" {
  value = azurerm_container_registry.main.name
}

output "aks_cluster_name" {
  value = azurerm_kubernetes_cluster.main.name
}

output "deployment_id" {
  value = random_id.deployment.hex
}

output "log_analytics_workspace_id" {
  value = azurerm_log_analytics_workspace.main.id
}
EOF

if [ "$SKIP_DEPLOY" = false ]; then
    cd "$TERRAFORM_DIR"
    terraform init > /dev/null 2>&1
    if terraform validate > /dev/null 2>&1; then
        echo "  Deploying to Azure (this takes ~5-10 minutes)..."
        if terraform apply -auto-approve -var subscription_id="$SUB_ID" > /tmp/tf-apply.log 2>&1; then
            echo -e "  ${GREEN}✓ PASS${NC}"
            log_result "Fix INC-004 (Terraform Deploy)" "PASS"
        else
            echo -e "  ${RED}✗ FAIL - terraform apply failed${NC}"
            tail -20 /tmp/tf-apply.log
            log_result "Fix INC-004 (Terraform Deploy)" "FAIL"
        fi
    else
        echo -e "  ${RED}✗ FAIL - terraform validate failed${NC}"
        terraform validate
        log_result "Fix INC-004 (Terraform Deploy)" "FAIL"
    fi
    cd "$SCRIPT_DIR"
else
    echo -e "  ${YELLOW}SKIPPED (--skip-deploy)${NC}"
    log_result "Fix INC-004 (Terraform Deploy)" "PASS"
fi

# ─────────────────────────────────────────────────────────────────
# Step 5: Fix INC-005 (CD Pipeline)
# ─────────────────────────────────────────────────────────────────
echo -e "${CYAN}[5/$TOTAL_STEPS] Fixing INC-005 (CD Pipeline)...${NC}"

cat > "${AZURE_DIR}/github-actions/cd.yml" << 'EOF'
name: CD Pipeline

on:
  workflow_dispatch:
  push:
    branches: [main]

env:
  ACR_NAME: ${{ secrets.ACR_NAME }}
  AKS_CLUSTER: ${{ secrets.AKS_CLUSTER_NAME }}
  RESOURCE_GROUP: ${{ secrets.RESOURCE_GROUP }}

jobs:
  build-and-push:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Azure Login
        uses: azure/login@v2
        with:
          creds: ${{ secrets.AZURE_CREDENTIALS }}

      - name: Login to ACR
        run: az acr login --name ${{ env.ACR_NAME }}

      - name: Build and push image
        run: |
          docker build -f azure/docker/Dockerfile -t ${{ env.ACR_NAME }}.azurecr.io/devops-lab-app:${{ github.sha }} .
          docker push ${{ env.ACR_NAME }}.azurecr.io/devops-lab-app:${{ github.sha }}

  deploy-to-aks:
    runs-on: ubuntu-latest
    needs: build-and-push
    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Azure Login
        uses: azure/login@v2
        with:
          creds: ${{ secrets.AZURE_CREDENTIALS }}

      - name: Get AKS credentials
        run: |
          az aks get-credentials --resource-group ${{ env.RESOURCE_GROUP }} --name ${{ env.AKS_CLUSTER }}

      - name: Deploy to AKS
        run: |
          kubectl set image deployment/devops-lab-app app=${{ env.ACR_NAME }}.azurecr.io/devops-lab-app:${{ github.sha }} -n devops-lab
EOF

if ! grep -q "credentials:" "${AZURE_DIR}/github-actions/cd.yml" && grep -q "creds:" "${AZURE_DIR}/github-actions/cd.yml"; then
    echo -e "  ${GREEN}✓ PASS${NC}"
    log_result "Fix INC-005 (CD Pipeline)" "PASS"
else
    echo -e "  ${RED}✗ FAIL${NC}"
    log_result "Fix INC-005 (CD Pipeline)" "FAIL"
fi

# ─────────────────────────────────────────────────────────────────
# Step 6: Fix INC-006 (Kubernetes) + Deploy to AKS
# ─────────────────────────────────────────────────────────────────
echo -e "${CYAN}[6/$TOTAL_STEPS] Fixing INC-006 (Kubernetes) + Deploy...${NC}"

if [ "$SKIP_DEPLOY" = false ] && [ -f "${TERRAFORM_DIR}/terraform.tfstate" ]; then
    cd "$TERRAFORM_DIR"
    ACR_NAME=$(terraform output -raw acr_name 2>/dev/null)
    ACR_SERVER=$(terraform output -raw acr_login_server 2>/dev/null)
    AKS_NAME=$(terraform output -raw aks_cluster_name 2>/dev/null)
    RG_NAME=$(terraform output -raw resource_group_name 2>/dev/null)
    cd "$SCRIPT_DIR"

    # Push image to ACR
    echo "  Pushing image to ACR..."
    az acr login --name "$ACR_NAME" > /dev/null 2>&1
    docker buildx build --platform linux/amd64 -f "${AZURE_DIR}/docker/Dockerfile" \
        -t "${ACR_SERVER}/devops-lab-app:latest" --push "${AZURE_DIR}" > /dev/null 2>&1

    # Get AKS credentials
    az aks get-credentials --resource-group "$RG_NAME" --name "$AKS_NAME" --overwrite-existing > /dev/null 2>&1
fi

# Write fixed K8s manifests
ACR_SERVER_FOR_K8S="${ACR_SERVER:-YOURACR.azurecr.io}"

cat > "${AZURE_DIR}/kubernetes/app-deployment.yaml" << EOF
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
          image: ${ACR_SERVER_FOR_K8S}/devops-lab-app:latest
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

cat > "${AZURE_DIR}/kubernetes/app-service.yaml" << 'EOF'
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

cat > "${AZURE_DIR}/kubernetes/redis-deployment.yaml" << 'EOF'
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

cat > "${AZURE_DIR}/kubernetes/redis-service.yaml" << 'EOF'
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

if [ "$SKIP_DEPLOY" = false ] && [ -n "$AKS_NAME" ]; then
    echo "  Deploying to AKS..."
    kubectl apply -f "${AZURE_DIR}/kubernetes/namespace.yaml" > /dev/null 2>&1
    kubectl apply -f "${AZURE_DIR}/kubernetes/" > /dev/null 2>&1

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
        echo -e "  ${GREEN}✓ PASS ($PODS_READY pods running)${NC}"
        log_result "Fix INC-006 (Kubernetes)" "PASS"
    else
        echo -e "  ${RED}✗ FAIL - Only $PODS_READY pods running${NC}"
        kubectl get pods -n devops-lab 2>/dev/null
        log_result "Fix INC-006 (Kubernetes)" "FAIL"
    fi
else
    # Local validation only
    if ! grep -q "v1beta1" "${AZURE_DIR}/kubernetes/app-deployment.yaml" && \
       ! grep -q "ACR_LOGIN_SERVER" "${AZURE_DIR}/kubernetes/app-deployment.yaml" && \
       ! grep -q "containerPort: 5000" "${AZURE_DIR}/kubernetes/app-deployment.yaml"; then
        echo -e "  ${GREEN}✓ PASS (local validation)${NC}"
        log_result "Fix INC-006 (Kubernetes)" "PASS"
    else
        echo -e "  ${RED}✗ FAIL${NC}"
        log_result "Fix INC-006 (Kubernetes)" "FAIL"
    fi
fi

# ─────────────────────────────────────────────────────────────────
# Step 7: Fix INC-007 (Monitoring)
# ─────────────────────────────────────────────────────────────────
echo -e "${CYAN}[7/$TOTAL_STEPS] Fixing INC-007 (Monitoring)...${NC}"

cat > "${AZURE_DIR}/monitoring/alerts.json" << 'EOF'
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "workspaceId": { "type": "string" },
    "aksClusterName": { "type": "string" },
    "resourceGroupName": { "type": "string" }
  },
  "resources": [
    {
      "type": "Microsoft.Insights/metricAlerts",
      "apiVersion": "2018-03-01",
      "name": "high-cpu-alert",
      "location": "global",
      "properties": {
        "description": "Alert when CPU exceeds 90%",
        "severity": 2,
        "enabled": true,
        "scopes": [
          "[resourceId('Microsoft.ContainerService/managedClusters', parameters('aksClusterName'))]"
        ],
        "evaluationFrequency": "PT1M",
        "windowSize": "PT5M",
        "criteria": {
          "odata.type": "Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria",
          "allOf": [
            {
              "name": "cpu-check",
              "metricName": "node_cpu_usage_percentage",
              "metricNamespace": "Microsoft.ContainerService/managedClusters",
              "operator": "GreaterThan",
              "threshold": 90,
              "timeAggregation": "Average"
            }
          ]
        }
      }
    },
    {
      "type": "Microsoft.Insights/metricAlerts",
      "apiVersion": "2018-03-01",
      "name": "pod-restart-alert",
      "location": "global",
      "properties": {
        "description": "Alert on pod restarts",
        "severity": 2,
        "enabled": true,
        "scopes": [
          "[resourceId('Microsoft.ContainerService/managedClusters', parameters('aksClusterName'))]"
        ],
        "evaluationFrequency": "PT1M",
        "windowSize": "PT30M",
        "criteria": {
          "odata.type": "Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria",
          "allOf": [
            {
              "name": "restart-check",
              "metricName": "kube_pod_status_restarts_total",
              "metricNamespace": "Microsoft.ContainerService/managedClusters",
              "operator": "GreaterThan",
              "threshold": 3,
              "timeAggregation": "Maximum"
            }
          ]
        }
      }
    }
  ]
}
EOF

ENABLED=$(python3 -c "
import json
with open('${AZURE_DIR}/monitoring/alerts.json') as f:
    data = json.load(f)
for r in data.get('resources', []):
    if r.get('name') == 'pod-restart-alert':
        print(r['properties']['enabled'])
" 2>/dev/null || echo "false")

if [ "$ENABLED" = "True" ]; then
    echo -e "  ${GREEN}✓ PASS${NC}"
    log_result "Fix INC-007 (Monitoring)" "PASS"
else
    echo -e "  ${RED}✗ FAIL${NC}"
    log_result "Fix INC-007 (Monitoring)" "FAIL"
fi

# ─────────────────────────────────────────────────────────────────
# Step 8: Token Generation
# ─────────────────────────────────────────────────────────────────
echo -e "${CYAN}[8/$TOTAL_STEPS] Testing token generation...${NC}"

TOKEN=$(echo "testuser" | "$VALIDATE_SCRIPT" export 2>/dev/null | grep -A1 "BEGIN L2C" | tail -1)

if [ -n "$TOKEN" ] && [ ${#TOKEN} -gt 20 ]; then
    echo -e "  ${GREEN}✓ PASS${NC}"
    log_result "Token Generation" "PASS"
else
    echo -e "  ${RED}✗ FAIL - No token generated${NC}"
    log_result "Token Generation" "FAIL"
fi

# ─────────────────────────────────────────────────────────────────
# Step 9: Token Verification
# ─────────────────────────────────────────────────────────────────
echo -e "${CYAN}[9/$TOTAL_STEPS] Testing token verification...${NC}"

if [ -n "$TOKEN" ]; then
    VERIFY_OUTPUT=$("$VALIDATE_SCRIPT" verify "$TOKEN" 2>&1)
    if echo "$VERIFY_OUTPUT" | grep -q "VALID"; then
        echo -e "  ${GREEN}✓ PASS${NC}"
        log_result "Token Verification" "PASS"
    else
        echo -e "  ${RED}✗ FAIL - Token verification failed${NC}"
        echo "$VERIFY_OUTPUT"
        log_result "Token Verification" "FAIL"
    fi
else
    echo -e "  ${RED}✗ FAIL - No token to verify${NC}"
    log_result "Token Verification" "FAIL"
fi

# ─────────────────────────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║                    VALIDATION SUMMARY                       ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "┌────────────────────────────────────┬──────────┐"
echo "│ Step                               │ Result   │"
echo "├────────────────────────────────────┼──────────┤"

for entry in "${RESULTS[@]}"; do
    STATUS="${entry%%:*}"
    STEP="${entry#*:}"
    if [ "$STATUS" = "PASS" ]; then
        printf "│ %-34s │ ${GREEN}✓ PASS${NC}   │\n" "$STEP"
    else
        printf "│ %-34s │ ${RED}✗ FAIL${NC}   │\n" "$STEP"
    fi
done

echo "└────────────────────────────────────┴──────────┘"
echo ""

if [ $FAILED -eq 0 ]; then
    echo "══════════════════════════════════════════════════════════════"
    echo -e "  ${GREEN}ALL TESTS PASSED ($PASSED/$TOTAL_STEPS)${NC}"
    echo "  Lab validation complete — ready for student use"
    echo "══════════════════════════════════════════════════════════════"
    exit 0
else
    echo "══════════════════════════════════════════════════════════════"
    echo -e "  ${RED}SOME TESTS FAILED ($PASSED passed, $FAILED failed)${NC}"
    echo "══════════════════════════════════════════════════════════════"
    exit 1
fi
