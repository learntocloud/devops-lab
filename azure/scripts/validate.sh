#!/usr/bin/env bash
# =============================================================================
# DEVOPS LAB - VALIDATION SCRIPT
# Validates incident resolution and generates completion tokens
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AZURE_DIR="${SCRIPT_DIR}/.."
TERRAFORM_DIR="${AZURE_DIR}/terraform"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

INC_001="pending"
INC_002="pending"
INC_003="pending"
INC_004="pending"
INC_005="pending"
INC_006="pending"
INC_007="pending"

MASTER_SECRET="L2C_CTF_MASTER_2024"

# =============================================================================
# INC-001: Dockerfile
# =============================================================================
validate_inc_001() {
    local DOCKERFILE="${AZURE_DIR}/docker/Dockerfile"
    [ ! -f "$DOCKERFILE" ] && return

    if docker build -f "$DOCKERFILE" -t devops-lab-app-test "${AZURE_DIR}" > /dev/null 2>&1; then
        local CID
        CID=$(docker run -d -p 18000:8000 -e REDIS_HOST=localhost devops-lab-app-test 2>/dev/null || echo "")
        if [ -n "$CID" ]; then
            sleep 3
            local RESP
            RESP=$(curl -s --max-time 5 http://localhost:18000/health 2>/dev/null || echo "")
            docker rm -f "$CID" > /dev/null 2>&1 || true
            if echo "$RESP" | grep -q "healthy"; then
                INC_001="resolved"
            fi
        fi
        docker rmi devops-lab-app-test > /dev/null 2>&1 || true
    fi
}

# =============================================================================
# INC-002: Docker Compose
# =============================================================================
validate_inc_002() {
    local COMPOSE="${AZURE_DIR}/docker/docker-compose.yml"
    [ ! -f "$COMPOSE" ] && return

    if ! docker compose -f "$COMPOSE" config > /dev/null 2>&1; then
        return
    fi

    docker compose -f "$COMPOSE" up -d --build > /dev/null 2>&1 || true
    sleep 5

    local RESP
    RESP=$(curl -s --max-time 5 http://localhost:8000/health 2>/dev/null || echo "")
    docker compose -f "$COMPOSE" down > /dev/null 2>&1 || true

    if echo "$RESP" | grep -q '"redis":"connected"'; then
        INC_002="resolved"
    fi
}

# =============================================================================
# INC-003: CI Workflow
# =============================================================================
validate_inc_003() {
    local CI="${AZURE_DIR}/github-actions/ci.yml"
    [ ! -f "$CI" ] && return

    # Valid YAML?
    if ! python3 -c "import yaml; yaml.safe_load(open('$CI'))" 2>/dev/null; then
        return
    fi

    # No invalid action versions
    if grep -q "@v99" "$CI" 2>/dev/null; then return; fi

    # Has runs-on
    if ! grep -q "runs-on:" "$CI" 2>/dev/null; then return; fi

    # Steps order: install before test
    local INSTALL_LINE TEST_LINE
    INSTALL_LINE=$(grep -n "Install dependencies" "$CI" 2>/dev/null | head -1 | cut -d: -f1)
    TEST_LINE=$(grep -n "Run tests" "$CI" 2>/dev/null | head -1 | cut -d: -f1)

    if [ -n "$INSTALL_LINE" ] && [ -n "$TEST_LINE" ]; then
        if [ "$TEST_LINE" -lt "$INSTALL_LINE" ]; then return; fi
    fi

    INC_003="resolved"
}

# =============================================================================
# INC-004: Terraform
# =============================================================================
validate_inc_004() {
    local TF="${AZURE_DIR}/terraform"
    [ ! -f "${TF}/main.tf" ] && return

    # Known typos
    if grep -q "azurerm_resouce_group" "${TF}/main.tf" 2>/dev/null; then return; fi
    if grep -q '"ACRPull"' "${TF}/main.tf" 2>/dev/null; then return; fi

    # Overlapping service CIDR
    if grep -q 'service_cidr.*=.*"10\.0\.' "${TF}/main.tf" 2>/dev/null; then return; fi

    cd "$TF"
    if terraform init -backend=false > /dev/null 2>&1 && terraform validate > /dev/null 2>&1; then
        INC_004="resolved"
    fi
    cd "$SCRIPT_DIR"
}

# =============================================================================
# INC-005: CD Workflow
# =============================================================================
validate_inc_005() {
    local CD="${AZURE_DIR}/github-actions/cd.yml"
    [ ! -f "$CD" ] && return

    if ! python3 -c "import yaml; yaml.safe_load(open('$CD'))" 2>/dev/null; then return; fi
    if ! grep -q "azure/login@v2" "$CD" 2>/dev/null; then return; fi
    if grep -q "credentials:" "$CD" 2>/dev/null; then return; fi
    if ! grep -q "kubectl" "$CD" 2>/dev/null; then return; fi

    INC_005="resolved"
}

# =============================================================================
# INC-006: Kubernetes
# =============================================================================
validate_inc_006() {
    local K="${AZURE_DIR}/kubernetes"
    [ ! -f "${K}/app-deployment.yaml" ] && return

    # Wrong API version
    if grep -q "v1beta1" "${K}/app-deployment.yaml" 2>/dev/null; then return; fi

    # Check app label selectors match
    local SEL TMPL
    SEL=$(grep -A2 "matchLabels" "${K}/app-deployment.yaml" 2>/dev/null | grep "app:" | head -1 | awk '{print $2}')
    TMPL=$(sed -n '/template:/,$ p' "${K}/app-deployment.yaml" 2>/dev/null | grep -A2 "labels:" | grep "app:" | head -1 | awk '{print $2}')
    if [ "$SEL" != "$TMPL" ]; then return; fi

    # Redis labels
    local RSEL RTMPL
    RSEL=$(grep -A2 "matchLabels" "${K}/redis-deployment.yaml" 2>/dev/null | grep "app:" | head -1 | awk '{print $2}')
    RTMPL=$(sed -n '/template:/,$ p' "${K}/redis-deployment.yaml" 2>/dev/null | grep -A2 "labels:" | grep "app:" | head -1 | awk '{print $2}')
    if [ "$RSEL" != "$RTMPL" ]; then return; fi

    # Redis port
    if grep -q "containerPort: 6380" "${K}/redis-deployment.yaml" 2>/dev/null; then return; fi

    # Placeholder ACR
    if grep -q "ACR_LOGIN_SERVER" "${K}/app-deployment.yaml" 2>/dev/null; then return; fi

    # Wrong readiness probe
    if grep -q "/ready" "${K}/app-deployment.yaml" 2>/dev/null; then return; fi

    # Wrong app port
    if grep -q "containerPort: 5000" "${K}/app-deployment.yaml" 2>/dev/null; then return; fi

    INC_006="resolved"
}

# =============================================================================
# INC-007: Monitoring
# =============================================================================
validate_inc_007() {
    local ALERTS="${AZURE_DIR}/monitoring/alerts.json"
    [ ! -f "$ALERTS" ] && return

    local ENABLED SEVERITY FREQ
    ENABLED=$(python3 -c "
import json
with open('$ALERTS') as f:
    data = json.load(f)
for r in data.get('resources', []):
    if r.get('name') == 'pod-restart-alert':
        print(r['properties']['enabled'])
" 2>/dev/null || echo "false")

    SEVERITY=$(python3 -c "
import json
with open('$ALERTS') as f:
    data = json.load(f)
for r in data.get('resources', []):
    if r.get('name') == 'pod-restart-alert':
        print(r['properties']['severity'])
" 2>/dev/null || echo "")

    FREQ=$(python3 -c "
import json
with open('$ALERTS') as f:
    data = json.load(f)
for r in data.get('resources', []):
    if r.get('name') == 'pod-restart-alert':
        print(r['properties']['evaluationFrequency'])
" 2>/dev/null || echo "")

    if [ "$ENABLED" = "True" ] && [ "$SEVERITY" = "2" ] && [ "$FREQ" = "PT1M" ]; then
        INC_007="resolved"
    fi
}

# =============================================================================
# Token Generation
# =============================================================================
get_deployment_id() {
    if [ -f "${TERRAFORM_DIR}/terraform.tfstate" ]; then
        cd "$TERRAFORM_DIR"
        local DID
        DID=$(terraform output -raw deployment_id 2>/dev/null || echo "")
        cd "$SCRIPT_DIR"
        if [ -n "$DID" ]; then
            echo "$DID"
            return
        fi
    fi
    echo "local-$(date +%s | shasum -a 256 | head -c 16)"
}

generate_verification_token() {
    local GITHUB_USER="$1"
    local DEPLOYMENT_ID
    DEPLOYMENT_ID=$(get_deployment_id)

    local TIMESTAMP=$(date +%s)
    local COMPLETION_DATE=$(date -u +"%Y-%m-%d")
    local COMPLETION_TIME=$(date -u +"%H:%M:%S")

    local VERIFICATION_SECRET
    VERIFICATION_SECRET=$(echo -n "${MASTER_SECRET}:${DEPLOYMENT_ID}" | shasum -a 256 | cut -d' ' -f1)

    local PAYLOAD='{"github_username":"'"$GITHUB_USER"'","date":"'"$COMPLETION_DATE"'","time":"'"$COMPLETION_TIME"'","timestamp":'"$TIMESTAMP"',"challenge":"devops-lab-azure","challenges":7,"instance_id":"'"$DEPLOYMENT_ID"'"}'

    local SIGNATURE
    SIGNATURE=$(echo -n "$PAYLOAD" | openssl dgst -sha256 -hmac "$VERIFICATION_SECRET" | sed 's/^.* //')

    local TOKEN_DATA='{"payload":'"$PAYLOAD"',"signature":"'"$SIGNATURE"'"}'
    echo -n "$TOKEN_DATA" | base64
}

# =============================================================================
# Display
# =============================================================================
show_status() {
    echo ""
    echo "============================================"
    echo "  DevOps Lab - Incident Status"
    echo "============================================"

    local RESOLVED=0

    for INC_VAR in INC_001 INC_002 INC_003 INC_004 INC_005 INC_006 INC_007; do
        local NUM="${INC_VAR#INC_}"
        local LABEL=""
        case "$NUM" in
            001) LABEL="Dockerfile" ;;
            002) LABEL="Docker Compose" ;;
            003) LABEL="CI Pipeline" ;;
            004) LABEL="Terraform" ;;
            005) LABEL="CD Pipeline" ;;
            006) LABEL="Kubernetes" ;;
            007) LABEL="Monitoring" ;;
        esac

        local STATUS="${!INC_VAR}"
        if [ "$STATUS" = "resolved" ]; then
            echo -e "  ${GREEN}✓${NC} INC-${NUM} - ${LABEL}"
            RESOLVED=$((RESOLVED + 1))
        else
            echo -e "  ${RED}✗${NC} INC-${NUM} - ${LABEL}"
        fi
    done

    echo ""
    echo "  Resolved: $RESOLVED / 7"
    echo ""

    if [ $RESOLVED -eq 7 ]; then
        echo -e "${GREEN}============================================${NC}"
        echo -e "${GREEN}   ALL INCIDENTS RESOLVED${NC}"
        echo -e "${GREEN}============================================${NC}"
        echo ""
        echo -e "  Run ${CYAN}./validate.sh export${NC} to generate"
        echo "  your completion token."
        echo ""
    fi
}

export_token() {
    validate_inc_001
    validate_inc_002
    validate_inc_003
    validate_inc_004
    validate_inc_005
    validate_inc_006
    validate_inc_007

    local RESOLVED=0
    for INC_VAR in INC_001 INC_002 INC_003 INC_004 INC_005 INC_006 INC_007; do
        [ "${!INC_VAR}" = "resolved" ] && RESOLVED=$((RESOLVED + 1))
    done

    if [ $RESOLVED -ne 7 ]; then
        show_status
        echo -e "${RED}Error: Not all incidents resolved.${NC}"
        exit 1
    fi

    echo ""
    echo -e "${GREEN}============================================${NC}"
    echo -e "${GREEN}   DEVOPS LAB - EXPORT TOKEN${NC}"
    echo -e "${GREEN}============================================${NC}"
    echo ""
    echo "Enter your GitHub username:"
    echo -n "> "
    read GITHUB_USER

    if [ -z "$GITHUB_USER" ]; then
        echo -e "${RED}Error: GitHub username required.${NC}"
        exit 1
    fi

    echo ""
    echo "Generating completion token..."
    echo ""

    local TOKEN
    TOKEN=$(generate_verification_token "$GITHUB_USER")

    echo -e "${GREEN}Your completion token:${NC}"
    echo ""
    echo "--- BEGIN L2C DEVOPS LAB TOKEN ---"
    echo "$TOKEN"
    echo "--- END L2C DEVOPS LAB TOKEN ---"
    echo ""
    echo "Token details:"
    echo "  GitHub User: $GITHUB_USER"
    echo "  Challenge:   devops-lab-azure"
    echo "  Completed:   $(date -u +"%Y-%m-%d %H:%M:%S UTC")"
    echo ""
    echo -e "${CYAN}Submit this token at: https://learntocloud.guide${NC}"
    echo ""
}

verify_token() {
    local TOKEN="$1"
    [ -z "$TOKEN" ] && echo "Usage: $0 verify <token>" && exit 1

    echo ""
    echo "Verifying token..."

    local DECODED
    DECODED=$(echo "$TOKEN" | base64 -d 2>/dev/null || echo "")
    [ -z "$DECODED" ] && echo -e "${RED}Error: Invalid token.${NC}" && exit 1

    local PAYLOAD PROVIDED_SIG INSTANCE_ID
    PAYLOAD=$(echo "$DECODED" | python3 -c "import sys,json; d=json.load(sys.stdin); print(json.dumps(d['payload'],separators=(',',':')))" 2>/dev/null)
    PROVIDED_SIG=$(echo "$DECODED" | python3 -c "import sys,json; print(json.load(sys.stdin)['signature'])" 2>/dev/null)
    INSTANCE_ID=$(echo "$DECODED" | python3 -c "import sys,json; print(json.load(sys.stdin)['payload']['instance_id'])" 2>/dev/null)

    [ -z "$PAYLOAD" ] || [ -z "$PROVIDED_SIG" ] && echo -e "${RED}Error: Parse failed.${NC}" && exit 1

    local VSECRET EXPECTED_SIG
    VSECRET=$(echo -n "${MASTER_SECRET}:${INSTANCE_ID}" | shasum -a 256 | cut -d' ' -f1)
    EXPECTED_SIG=$(echo -n "$PAYLOAD" | openssl dgst -sha256 -hmac "$VSECRET" | sed 's/^.* //')

    if [ "$PROVIDED_SIG" = "$EXPECTED_SIG" ]; then
        echo -e "${GREEN}✓ Token is VALID${NC}"
        echo ""
        echo "$DECODED" | python3 -c "import sys,json; d=json.load(sys.stdin); [print(f'  {k}: {v}') for k,v in d['payload'].items()]"
    else
        echo -e "${RED}✗ Token is INVALID${NC}"
        exit 1
    fi
    echo ""
}

# =============================================================================
# Main
# =============================================================================
main() {
    local CMD="${1:-status}"
    case "$CMD" in
        status|all)
            validate_inc_001
            validate_inc_002
            validate_inc_003
            validate_inc_004
            validate_inc_005
            validate_inc_006
            validate_inc_007
            show_status
            ;;
        export) export_token ;;
        verify) verify_token "$2" ;;
        *) echo "Usage: $0 [status|export|verify <token>]" ;;
    esac
}

main "$@"
