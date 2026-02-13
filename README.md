# DevOps Lab

Fix a broken DevOps pipeline. Learn by troubleshooting real-world misconfigurations.

## Overview

You've just joined a startup as the DevOps engineer. The previous engineer left, and the entire CI/CD pipeline is broken. The team can't build, test, or deploy their application. Your mission: fix everything and get the pipeline running.

## Challenges

| # | Incident | Category | Difficulty | Skills |
|---|----------|----------|------------|--------|
| 1 | Container image won't build | Docker | ⭐ | Dockerfile syntax, image layers, dependencies |
| 2 | Local dev environment broken | Docker Compose | ⭐⭐ | Compose files, networking, service dependencies |
| 3 | CI pipeline is broken | GitHub Actions | ⭐⭐ | Workflow YAML, actions, job configuration |
| 4 | Terraform can't provision infrastructure | IaC (Terraform) | ⭐⭐ | HCL syntax, Azure resources, managed identity |
| 5 | Deployment pipeline failing | GitHub Actions CD | ⭐⭐⭐ | CD workflows, ACR, AKS deployment |
| 6 | Kubernetes deployment crashing | Kubernetes | ⭐⭐⭐ | Deployments, services, probes, selectors |
| 7 | Monitoring not working | Observability | ⭐⭐⭐ | Azure Monitor, Container Insights, alerts |

**Difficulty:** ⭐ Beginner | ⭐⭐ Intermediate | ⭐⭐⭐ Advanced

## Choose Your Cloud

| Provider | Status | Guide |
|----------|--------|-------|
| Azure | ✅ Available | [azure/README.md](azure/README.md) |
| AWS | ✅ Available | [aws/README.md](aws/README.md) |
| GCP | 🚧 Coming soon | — |

## How It Works

1. Clone this repo
2. Follow the cloud-specific setup guide to deploy the broken infrastructure
3. Work through the incident queue — diagnose and fix each issue
4. Run `validate.sh` to check your progress
5. When all incidents are resolved, export your completion token
6. Destroy your resources when done

## Verification

After resolving all incidents, generate your completion token:

```bash
cd azure/scripts
./validate.sh export
```

Submit your token at [learntocloud.guide](https://learntocloud.guide) to verify your completion.

## Cost

~$3-5 per session (Azure). **Always destroy resources when done.**

## License

[MIT License](LICENSE)

## Contributing

Want to help improve the lab? See our [Contributing Guide](CONTRIBUTING.md).

Please only submit issues about the lab infrastructure, not for help completing challenges — struggling is part of learning!
