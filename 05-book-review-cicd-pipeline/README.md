# Book Review — Full CI/CD Pipeline

Implemented a production-grade, two-repository CI/CD architecture separating
infrastructure and application concerns — mirroring how platform and
application teams operate in professional engineering organisations.

## Architecture
```
book-review-infra repo              book-review-app repo
(Infrastructure team)               (Application team)
        |                                   |
Azure DevOps Pipeline               Azure DevOps Pipeline
        |                                   |
  Terraform apply                     Ansible deploy
        |                                   |
Azure VMs + MySQL DB  ── IPs ──>  Frontend + Backend (PM2)
```

## What Was Built

- Terraform code provisioning Azure frontend VM, backend VM, and MySQL database
- Ansible playbooks deploying the Node.js backend and Next.js frontend with PM2
- Two independent Azure DevOps YAML pipelines (infra pipeline + app pipeline)
- SSH keys stored as Secure Files in Azure DevOps Library — never in source code
- Azure Service Principal registered as a Service Connection for Terraform authentication
- Branch-triggered deployments: every push to `main` triggers a redeploy
- Manual IP handoff between infra and app pipelines modelled explicitly (reflects real team boundaries)

## Security Practices Applied

- SSH private key managed exclusively through Azure DevOps Library
- Azure credentials injected via Service Principal, not hardcoded
- Secrets never committed to source control

## Tools

Terraform · Ansible · Azure DevOps · Azure Cloud (VMs + MySQL) · PM2 · GitHub · SSH
