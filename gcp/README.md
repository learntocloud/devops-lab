# GCP DevOps Lab

Fix a broken DevOps pipeline deployed to Google Cloud. Work through 7 incidents to get the application running.

```
┌─────────────────────────────────────────────────────────────┐
│                    GCP Resources                            │
│                                                             │
│  ┌──────────┐   ┌─────────────────┐   ┌──────────────────┐ │
│  │   VPC    │   │ Artifact Reg.   │   │       GKE        │ │
│  │          │   │   (images)      │──▶│  ┌─────┐ ┌──────┐ │ │
│  │  Subnet  │   │                 │   │  │ App │ │Redis │ │ │
│  │          │   └─────────────────┘   │  └─────┘ └──────┘ │ │
│  └──────────┘                         └──────────────────┘ │
│                                                             │
│  ┌──────────────────┐  ┌───────────────────────────────┐   │
│  │ Cloud Logging    │  │      Cloud Monitoring         │   │
│  │   Workspace      │  │      Metrics + Alerts         │   │
│  └──────────────────┘  └───────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

## Prerequisites

- [Google Cloud CLI](https://cloud.google.com/sdk/docs/install)
- [Terraform](https://developer.hashicorp.com/terraform/install) (v1.0+)
- [Docker](https://docs.docker.com/get-docker/)
- [kubectl](https://kubernetes.io/docs/tasks/tools/)

## Getting Started

1. Clone this repo and navigate to the GCP scripts:
   ```bash
   git clone https://github.com/learntocloud/devops-lab
   cd devops-lab/gcp/scripts
   ```

2. Log in to Google Cloud:
   ```bash
   gcloud auth login
   gcloud auth application-default login
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

### INC-001: Container Image Won't Build

**Priority:** High  
**Reported by:** Development Team  
**Tools:** `docker` CLI

> "We can't build the app's Docker image. The `docker build` command fails immediately with errors. The Dockerfile is at `gcp/docker/Dockerfile`. We need the image to build successfully and the container to start and respond on the correct port."

**What to fix:** `gcp/docker/Dockerfile`

---

### INC-002: Local Dev Environment Broken

**Priority:** High  
**Reported by:** Development Team  
**Tools:** `docker compose` CLI

> "Docker Compose won't bring up our local environment. The app can't connect to Redis, and the port mapping seems wrong. The compose file is at `gcp/docker/docker-compose.yml`. We need both services (app + redis) to start and communicate."

**What to fix:** `gcp/docker/docker-compose.yml`

---

### INC-003: CI Pipeline is Broken

**Priority:** High  
**Reported by:** Engineering Manager  
**Tools:** GitHub Actions YAML reference

> "Our CI workflow has YAML errors and the steps are in the wrong order. Tests run before dependencies are installed, and some action versions look wrong. The workflow is at `gcp/github-actions/ci.yml`."

**What to fix:** `gcp/github-actions/ci.yml`

---

### INC-004: Terraform Can't Provision Infrastructure

**Priority:** Critical  
**Reported by:** Platform Team  
**Tools:** `terraform` CLI, `gcloud` CLI

> "Terraform plan fails with multiple errors. There are typos in resource names, IAM role bindings are wrong, and network ranges conflict. The config is at `gcp/terraform/`. We need the VPC, Artifact Registry, GKE cluster, and monitoring workspace to all deploy successfully."

**What to fix:** `gcp/terraform/main.tf`, `gcp/terraform/outputs.tf`

---

### INC-005: Deployment Pipeline Failing

**Priority:** High  
**Reported by:** Release Team  
**Tools:** GitHub Actions YAML reference, `gcloud` CLI

> "The CD pipeline can't deploy to GKE. The GCP auth action is misconfigured, and deployment steps are incomplete. The workflow is at `gcp/github-actions/cd.yml`."

**What to fix:** `gcp/github-actions/cd.yml`

---

### INC-006: Kubernetes Deployment Crashing

**Priority:** Critical  
**Reported by:** SRE Team  
**Tools:** `kubectl` CLI

> "Pods won't start in GKE. The deployments have wrong API versions, label selectors don't match between deployments and services, container ports are wrong, and the readiness probe is hitting an endpoint that doesn't exist. Manifests are in `gcp/kubernetes/`."

**What to fix:** `gcp/kubernetes/app-deployment.yaml`, `gcp/kubernetes/app-service.yaml`, `gcp/kubernetes/redis-deployment.yaml`, `gcp/kubernetes/redis-service.yaml`

---

### INC-007: Monitoring Not Working

**Priority:** Medium  
**Reported by:** Observability Team  
**Tools:** Cloud Monitoring alert policy JSON

> "The pod restart alert is disabled and should be enabled. Our monitoring config at `gcp/monitoring/alerts.json` needs fixing. The alert should be severity 2 (not 1), and should evaluate every 60 seconds (not 300)."

**What to fix:** `gcp/monitoring/alerts.json`

---

## Verify Your Fixes

Check incident status anytime:

```bash
cd gcp/scripts
./validate.sh
```

Generate your completion token after all incidents are resolved:

```bash
./validate.sh export
```

## Clean Up

**Always destroy resources when done to avoid charges:**

```bash
cd gcp/scripts
./destroy.sh
```
