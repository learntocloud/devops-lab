---
name: validate-devops-lab
description: |
  End-to-end validation of the DevOps Lab. Deploys broken infrastructure, applies fixes for all 7 incidents,
  validates each fix, generates and verifies a completion token, then destroys all resources.
  Supports Azure (AWS and GCP coming soon).
license: MIT
metadata:
  author: learntocloud
  version: "1.0"
compatibility: Requires Azure CLI, Terraform, Docker, kubectl, Python 3.x with PyYAML
---

# Validate DevOps Lab

Test the lab end-to-end: deploy broken state, apply fixes, validate, verify token, destroy.

## Prerequisites

- Azure CLI logged in (`az login`)
- Terraform installed
- Docker running
- kubectl installed
- Python 3.x with PyYAML (`pip install pyyaml`)

## Run Validation

### Azure

```bash
cd .github/skills/validate-devops-lab/azure/scripts
chmod +x *.sh
./run-full-validation.sh
```

Options:
- `--skip-deploy`: Skip deployment (use existing infrastructure)
- `--skip-destroy`: Skip resource cleanup (for debugging)

## What It Does

1. **Apply local fixes** — Fixes all 7 incidents (Dockerfile, Compose, CI, Terraform, CD, K8s, Monitoring)
2. **Validate locally** — Runs validate.sh to confirm INC-001 through INC-003 and INC-005 through INC-007
3. **Deploy infrastructure** — Terraform apply for fixed IaC (INC-004)
4. **Push to ACR** — Builds and pushes Docker image to Azure Container Registry
5. **Deploy to AKS** — Applies K8s manifests to the AKS cluster
6. **Validate deployed state** — Confirms pods running, services accessible
7. **Token test** — Generates token and verifies it
8. **Cleanup** — Destroys resource group and all resources

## Expected Output

```
╔══════════════════════════════════════════════════════════════╗
║                    VALIDATION SUMMARY                        ║
╚══════════════════════════════════════════════════════════════╝

┌────────────────────────────────────┬──────────┐
│ Step                               │ Result   │
├────────────────────────────────────┼──────────┤
│ Fix INC-001 (Dockerfile)           │ ✓ PASS   │
│ Fix INC-002 (Docker Compose)       │ ✓ PASS   │
│ Fix INC-003 (CI Pipeline)          │ ✓ PASS   │
│ Fix INC-004 (Terraform Deploy)     │ ✓ PASS   │
│ Fix INC-005 (CD Pipeline)          │ ✓ PASS   │
│ Fix INC-006 (Kubernetes)           │ ✓ PASS   │
│ Fix INC-007 (Monitoring)           │ ✓ PASS   │
│ Token Generation                   │ ✓ PASS   │
│ Token Verification                 │ ✓ PASS   │
└────────────────────────────────────┴──────────┘

  ALL TESTS PASSED (9/9)
```

Exit code 0 = all passed, exit code 1 = something failed.

## Important: Resource Cleanup

All resources are destroyed by deleting the resource group. This ensures no orphaned resources.

### Manual Cleanup

```bash
az group list --query "[?starts_with(name, 'rg-devopslab')]" -o table
az group delete -n <resource-group-name> --yes
```
