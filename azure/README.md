# Azure DevOps Lab

Fix a broken DevOps pipeline deployed to Azure. Work through 7 incidents to get the application running.

```
┌─────────────────────────────────────────────────────────────┐
│                    Azure Resources                          │
│                                                             │
│  ┌──────────┐   ┌──────────┐   ┌────────────────────────┐  │
│  │   VNet   │   │   ACR    │   │         AKS            │  │
│  │          │   │ (images) │──▶│  ┌─────┐  ┌───────┐    │  │
│  │  Subnet  │   │          │   │  │ App │──│ Redis │    │  │
│  │          │   └──────────┘   │  └─────┘  └───────┘    │  │
│  └──────────┘                  └────────────────────────┘  │
│                                                             │
│  ┌──────────────────┐  ┌───────────────────────────────┐   │
│  │  Log Analytics   │  │      Azure Monitor            │   │
│  │   Workspace      │  │   Container Insights + Alerts │   │
│  └──────────────────┘  └───────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

## Prerequisites

- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli)
- [Terraform](https://developer.hashicorp.com/terraform/install) (v1.0+)
- [Docker](https://docs.docker.com/get-docker/)
- [kubectl](https://kubernetes.io/docs/tasks/tools/)

## Getting Started

1. Clone this repo and navigate to the Azure scripts:
   ```bash
   git clone https://github.com/learntocloud/devops-lab
   cd devops-lab/azure/scripts
   ```

2. Log in to Azure:
   ```bash
   az login
   ```

3. Run the setup script:
   ```bash
   chmod +x *.sh
   ./setup.sh
   ```

**Cost**: ~$3-5/session. Destroy resources when done.

---

## Incident Queue

You're the new DevOps engineer. Seven incidents are waiting. Diagnose and fix each one.

---

### 🎫 INC-001: Container Image Won't Build

**Priority:** High  
**Reported by:** Development Team  
**Tools:** `docker` CLI

> "We can't build the app's Docker image. The `docker build` command fails immediately with errors. The Dockerfile is at `azure/docker/Dockerfile`. We need the image to build successfully and the container to start and respond on the correct port."

**What to fix:** `azure/docker/Dockerfile`

---

### 🎫 INC-002: Local Dev Environment Broken

**Priority:** High  
**Reported by:** Development Team  
**Tools:** `docker compose` CLI

> "Docker Compose won't bring up our local environment. The app can't connect to Redis, and the port mapping seems wrong. The compose file is at `azure/docker/docker-compose.yml`. We need both services (app + redis) to start and communicate."

**What to fix:** `azure/docker/docker-compose.yml`

---

### 🎫 INC-003: CI Pipeline is Broken

**Priority:** High  
**Reported by:** Engineering Manager  
**Tools:** GitHub Actions YAML reference

> "Our CI workflow has YAML errors and the steps are in the wrong order. Tests run before dependencies are installed, and some action versions look wrong. The workflow is at `azure/github-actions/ci.yml`."

**What to fix:** `azure/github-actions/ci.yml`

---

### 🎫 INC-004: Terraform Can't Provision Infrastructure

**Priority:** Critical  
**Reported by:** Platform Team  
**Tools:** `terraform` CLI, `az` CLI

> "Terraform plan fails with multiple errors. There are typos in resource types, something is wrong with the role assignments for our managed identity, and the network configuration has conflicts. The config is at `azure/terraform/`. We need the VNet, ACR, AKS cluster, and monitoring workspace to all deploy successfully."

**What to fix:** `azure/terraform/main.tf`, `azure/terraform/outputs.tf`

---

### 🎫 INC-005: Deployment Pipeline Failing

**Priority:** High  
**Reported by:** Release Team  
**Tools:** GitHub Actions YAML reference, `az` CLI

> "The CD pipeline can't deploy to AKS. The Azure login action is misconfigured, and the deployment steps aren't right. The workflow is at `azure/github-actions/cd.yml`."

**What to fix:** `azure/github-actions/cd.yml`

---

### 🎫 INC-006: Kubernetes Deployment Crashing

**Priority:** Critical  
**Reported by:** SRE Team  
**Tools:** `kubectl` CLI

> "Pods won't start in AKS. The deployments have wrong API versions, label selectors don't match between deployments and services, container ports are wrong, and the readiness probe is hitting an endpoint that doesn't exist. Manifests are in `azure/kubernetes/`."

**What to fix:** `azure/kubernetes/app-deployment.yaml`, `azure/kubernetes/app-service.yaml`, `azure/kubernetes/redis-deployment.yaml`, `azure/kubernetes/redis-service.yaml`

---

### 🎫 INC-007: Monitoring Not Working

**Priority:** Medium  
**Reported by:** Observability Team  
**Tools:** `az` CLI

> "The pod restart alert is disabled and should be enabled. We need Container Insights running on AKS, and our alert configuration at `azure/monitoring/alerts.json` needs fixing. The alert for pod restarts should be severity 2 (not 1), and it should evaluate every minute (not every 5 minutes)."

**What to fix:** `azure/monitoring/alerts.json`

---

## Verify Your Fixes

Check incident status anytime:

```bash
cd azure/scripts
./validate.sh
```

Generate your completion token after all incidents are resolved:

```bash
./validate.sh export
```

## Clean Up

**Always destroy resources when done to avoid charges:**

```bash
cd azure/scripts
./destroy.sh
```
