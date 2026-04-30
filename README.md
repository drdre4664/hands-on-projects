# Cloud & DevOps Engineering Portfolio

A collection of hands-on projects built while studying and applying real-world DevOps and cloud engineering skills. Each project solves a real infrastructure or deployment problem — from containerizing applications and automating deployments, to provisioning production-grade cloud infrastructure from code.

These are not tutorial follow-alongs. Every project was built, broken, debugged, and documented through hands-on work across Docker, Terraform, Ansible, Azure DevOps, AWS, and Azure.

---

## Projects

| Project | Description | Technologies |
|---------|-------------|--------------|
| [azure-vm-3tier-deployment](./01-3tier-azure-vm) | Provisioned an Azure VM from scratch using Cloud-Init to auto-install Docker on boot, then deployed a full 3-tier app (Nginx + Node.js + PostgreSQL) using Docker Compose — zero manual setup | Azure VM, Cloud-Init, Docker Compose, Nginx, PostgreSQL |
| [docker-containerized-fullstack](./02-book-review-containerized) | Containerized a full-stack Book Review application with JWT auth, REST API, and MySQL — orchestrated with Docker Compose so the entire stack spins up with one command | Docker, Docker Compose, Next.js, Node.js, MySQL, JWT |
| [docker-compose-nginx-reverse-proxy](./03-epicbook-compose-nginx) | Deployed a multi-service e-commerce bookstore with Nginx as a reverse proxy and strict network isolation — database unreachable from internet, frontend can only reach backend | Docker Compose, Nginx, Node.js, MongoDB, Network Isolation |
| [react-multistage-docker-build](./04-react-multistage-docker) | Built a production Docker image for a React app using a multi-stage build pattern — shrinking the final image from ~900MB down to ~25MB by separating the build environment from the runtime | Docker Multi-Stage, Nginx, React, Azure VM, Docker Hub |
| [cicd-pipeline-azure-devops](./05-book-review-cicd-pipeline) | Implemented a two-repository CI/CD architecture in Azure DevOps — infra pipeline runs Terraform to provision Azure resources, app pipeline runs Ansible to deploy the application. Secrets managed via DevOps Secure Files | Azure DevOps, Terraform, Ansible, Azure VMs, MySQL |
| [terraform-azure-3tier-infrastructure](./06-terraform-iaac) | Provisioned a complete 3-tier Azure infrastructure entirely from Terraform code — VNet, subnets, NSGs, VMs, Load Balancer, and MySQL Flexible Server — using a modular architecture with separate network, compute, and database modules | Terraform, Azure VNet, Azure VMs, MySQL Flexible Server, NSG, HCL |
| [ansible-role-based-deployment](./07-ansible-configuration-management) | Automated server configuration and application deployment using Ansible roles — common hardening, Nginx setup via Jinja2 templates, and app deployment — all idempotent and re-runnable safely | Ansible, Roles, Jinja2, Handlers, Idempotency, Ubuntu |
| [aws-azure-ha-cloud-architecture](./08-aws-azure-cloud-architecture) | Designed and built a production-grade highly available 3-tier architecture on both AWS and Azure — public + internal load balancers, Multi-AZ RDS, Auto Scaling, private subnets, NAT Gateway, and health checks | AWS EC2, VPC, ALB, RDS Multi-AZ, Auto Scaling, Azure VM, NSG |

---

## Skills Demonstrated

**Containerization**
Docker (multi-stage builds, Compose, Nginx reverse proxy, network isolation, named volumes)

**Infrastructure as Code**
Terraform (modular architecture, variable files, provider config, Azure + AWS)

**Configuration Management**
Ansible (role-based structure, Jinja2 templates, handlers, idempotency, group_vars)

**CI/CD Pipelines**
Azure DevOps (YAML pipelines, two-repo model, Secure Files, self-hosted agents)

**Cloud — AWS**
VPC, EC2, Application Load Balancer (public + internal), Auto Scaling Groups, RDS MySQL Multi-AZ + Read Replica, S3, IAM, CloudWatch, NAT Gateway

**Cloud — Azure**
Virtual Machines, VNet, NSG, Load Balancer, MySQL Flexible Server, Blob Storage, RBAC, Azure DevOps

**Architecture Patterns**
3-tier separation, Multi-AZ high availability, least-privilege security groups, health checks, private subnet isolation

---

## About This Repo

Built as part of a structured DevOps learning programme covering Linux, Docker, Kubernetes, Terraform, Ansible, CI/CD, AWS, and Azure. Projects progress from single-VM deployments through to fully automated, pipeline-driven, multi-cloud infrastructure.

All sensitive values (passwords, keys, credentials) are excluded via `.gitignore` or replaced with `.example` files. No real credentials are stored in this repository.
