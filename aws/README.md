# AWS DevOps Lab

Fix a broken DevOps pipeline deployed to AWS. Work through 7 incidents to get the application running.

```
┌─────────────────────────────────────────────────────────────┐
│                    AWS Resources                            │
│                                                             │
│  ┌──────────┐   ┌──────────┐   ┌────────────────────────┐  │
│  │   VPC    │   │   ECR    │   │         EKS            │  │
│  │          │   │ (images) │──▶│  ┌─────┐  ┌───────┐    │  │
│  │  Subnet  │   │          │   │  │ App │──│ Redis │    │  │
│  │          │   └──────────┘   │  └─────┘  └───────┘    │  │
│  └──────────┘                  └────────────────────────┘  │
│                                                             │
│  ┌──────────────────┐  ┌───────────────────────────────┐   │
│  │   CloudWatch     │  │     Container Insights        │   │
│  │   Log Group      │  │        + Alarms               │   │
│  └──────────────────┘  └───────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

## Prerequisites

- [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)
- [Terraform](https://developer.hashicorp.com/terraform/install) (v1.0+)
- [Docker](https://docs.docker.com/get-docker/)
- [kubectl](https://kubernetes.io/docs/tasks/tools/)

## Getting Started

1. Clone this repo and navigate to the AWS scripts:
   ```bash
   git clone https://github.com/learntocloud/devops-lab
   cd devops-lab/aws/scripts
   ```

2. Log in to AWS:
   ```bash
   aws configure
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

> "We can't build the app's Docker image. The `docker build` command fails immediately with errors. The Dockerfile is at `aws/docker/Dockerfile`. We need the image to build successfully and the container to start and respond on the correct port."

**What to fix:** `aws/docker/Dockerfile`

---

### 🎫 INC-002: Local Dev Environment Broken

**Priority:** High  
**Reported by:** Development Team  
**Tools:** `docker compose` CLI

> "Docker Compose won't bring up our local environment. The app can't connect to Redis, and the port mapping seems wrong. The compose file is at `aws/docker/docker-compose.yml`. We need both services (app + redis) to start and communicate."

**What to fix:** `aws/docker/docker-compose.yml`

---

### 🎫 INC-003: CI Pipeline is Broken

**Priority:** High  
**Reported by:** Engineering Manager  
**Tools:** GitHub Actions YAML reference

> "Our CI workflow has YAML errors and the steps are in the wrong order. Tests run before dependencies are installed, and some action versions look wrong. The workflow is at `aws/github-actions/ci.yml`."

**What to fix:** `aws/github-actions/ci.yml`

---

### 🎫 INC-004: Terraform Can't Provision Infrastructure

**Priority:** Critical  
**Reported by:** Platform Team  
**Tools:** `terraform` CLI, `aws` CLI

> "Terraform plan fails with multiple errors. There are typos in resource types, something is wrong with the IAM role policies, and the cluster networking configuration has conflicts. The config is at `aws/terraform/`. We need the VPC, ECR, EKS cluster, and monitoring log group to all deploy successfully."

**What to fix:** `aws/terraform/main.tf`, `aws/terraform/outputs.tf`

---

### 🎫 INC-005: Deployment Pipeline Failing

**Priority:** High  
**Reported by:** Release Team  
**Tools:** GitHub Actions YAML reference, `aws` CLI

> "The CD pipeline can't deploy to EKS. The AWS credentials action is misconfigured, and the deployment steps aren't right. The workflow is at `aws/github-actions/cd.yml`."

**What to fix:** `aws/github-actions/cd.yml`

---

### 🎫 INC-006: Kubernetes Deployment Crashing

**Priority:** Critical  
**Reported by:** SRE Team  
**Tools:** `kubectl` CLI

> "Pods won't start in EKS. The deployments have wrong API versions, label selectors don't match between deployments and services, container ports are wrong, and the readiness probe is hitting an endpoint that doesn't exist. Manifests are in `aws/kubernetes/`."

**What to fix:** `aws/kubernetes/app-deployment.yaml`, `aws/kubernetes/app-service.yaml`, `aws/kubernetes/redis-deployment.yaml`, `aws/kubernetes/redis-service.yaml`

---

### 🎫 INC-007: Monitoring Not Working

**Priority:** Medium  
**Reported by:** Observability Team  
**Tools:** `aws` CLI

> "The pod restart alarm is disabled and should be enabled. We need Container Insights running on EKS, and our alarm configuration at `aws/monitoring/alerts.json` needs fixing. The alarm for pod restarts should be severity 2 (not 1), and it should evaluate every minute (not every 5 minutes)."

**What to fix:** `aws/monitoring/alerts.json`

---

## Verify Your Fixes

Check incident status anytime:

```bash
cd aws/scripts
./validate.sh
```

Generate your completion token after all incidents are resolved:

```bash
./validate.sh export
```

## Clean Up

**Always destroy resources when done to avoid charges:**

```bash
cd aws/scripts
./destroy.sh
```
