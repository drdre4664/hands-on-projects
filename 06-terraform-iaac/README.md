# Project 06 — Terraform IaaC: AWS 3-Tier Architecture with High Availability

## Overview

Provisioned a production-grade, highly available 3-tier architecture on AWS using Terraform Infrastructure as Code. The deployment includes a custom VPC with 6 subnets across 2 Availability Zones, public and internal Application Load Balancers, Auto Scaling Groups, and a Multi-AZ RDS MySQL database with a Read Replica — all managed through modular, reusable Terraform code with remote S3 state.

## Architecture

```
Internet
    |
[Internet Gateway]
    |
[Public ALB] — sg_alb (port 80 inbound from 0.0.0.0/0)
    |
[Web Tier EC2 — Public Subnets AZ-1 & AZ-2]
    |   sg_web: allows port 80 from sg_alb only
    |
[Internal ALB] — sg_internal_alb (port 80 from sg_web only)
    |
[App Tier EC2 — Private Subnets AZ-1 & AZ-2]
    |   sg_app: allows port 3000 from sg_internal_alb only
    |   NO public IP assigned
    |
[RDS MySQL Multi-AZ + Read Replica]
    sg_db: allows port 3306 from sg_app ONLY
    [DB Subnets AZ-1 & AZ-2 — isolated tier]
```

## Project Goals

- Custom VPC with 6 subnets: 2 public (web tier), 2 private (app tier), 2 isolated DB subnets
- Web Tier EC2 instances in public subnets — no Elastic IPs attached
- App Tier EC2 instances in private subnets — no public IP address
- Public ALB for web tier with health check on `/health`
- Internal ALB for app tier with health check on `/health`
- RDS MySQL with Multi-AZ deployment and a Read Replica
- Least-privilege Security Groups between every tier
- DB Security Group allows only App Tier Security Group on port 3306

## Project Structure

```
06-terraform-iaac/
├── main.tf
├── variables.tf
├── outputs.tf
├── terraform.tfvars.example    ← template only; never commit a populated tfvars
└── modules/
    ├── network/
    │   ├── main.tf
    │   ├── variables.tf
    │   └── outputs.tf
    ├── compute/
    │   ├── main.tf
    │   ├── variables.tf
    │   └── outputs.tf
    └── database/
        ├── main.tf
        ├── variables.tf
        └── outputs.tf
```

## Terraform Configuration

### main.tf (Root)

```hcl
terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  backend "s3" {
    bucket = "your-terraform-state-bucket"
    key    = "prod/3tier/terraform.tfstate"
    region = "us-east-1"
  }
}

provider "aws" {
  region = var.aws_region
}

module "network" {
  source             = "./modules/network"
  vpc_cidr           = var.vpc_cidr
  public_subnets     = var.public_subnets
  private_subnets    = var.private_subnets
  db_subnets         = var.db_subnets
  availability_zones = var.availability_zones
  project_name       = var.project_name
}

module "compute" {
  source              = "./modules/compute"
  vpc_id              = module.network.vpc_id
  public_subnet_ids   = module.network.public_subnet_ids
  private_subnet_ids  = module.network.private_subnet_ids
  web_instance_type   = var.web_instance_type
  app_instance_type   = var.app_instance_type
  ami_id              = var.ami_id
  key_name            = var.key_name
  project_name        = var.project_name
  web_min_size        = var.web_min_size
  web_max_size        = var.web_max_size
  app_min_size        = var.app_min_size
  app_max_size        = var.app_max_size
}

module "database" {
  source            = "./modules/database"
  vpc_id            = module.network.vpc_id
  db_subnet_ids     = module.network.db_subnet_ids
  app_sg_id         = module.compute.app_sg_id
  db_name           = var.db_name
  db_username       = var.db_username
  db_password       = var.db_password
  db_instance_class = var.db_instance_class
  project_name      = var.project_name
}
```

### modules/network/main.tf

```hcl
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags = { Name = "${var.project_name}-vpc" }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.project_name}-igw" }
}

resource "aws_subnet" "public" {
  count                   = length(var.public_subnets)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnets[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true
  tags = { Name = "${var.project_name}-public-${count.index + 1}" }
}

resource "aws_subnet" "private" {
  count             = length(var.private_subnets)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnets[count.index]
  availability_zone = var.availability_zones[count.index]
  tags = { Name = "${var.project_name}-private-${count.index + 1}" }
}

resource "aws_subnet" "db" {
  count             = length(var.db_subnets)
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.db_subnets[count.index]
  availability_zone = var.availability_zones[count.index]
  tags = { Name = "${var.project_name}-db-${count.index + 1}" }
}

resource "aws_eip" "nat" { domain = "vpc" }

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id
  tags          = { Name = "${var.project_name}-nat" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  count          = length(aws_subnet.private)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

resource "aws_security_group" "alb" {
  name   = "${var.project_name}-alb-sg"
  vpc_id = aws_vpc.main.id
  ingress { from_port = 80; to_port = 80; protocol = "tcp"; cidr_blocks = ["0.0.0.0/0"] }
  egress  { from_port = 0;  to_port = 0;  protocol = "-1"; cidr_blocks = ["0.0.0.0/0"] }
}

resource "aws_security_group" "web" {
  name   = "${var.project_name}-web-sg"
  vpc_id = aws_vpc.main.id
  ingress { from_port = 80; to_port = 80; protocol = "tcp"; security_groups = [aws_security_group.alb.id] }
  egress  { from_port = 0;  to_port = 0;  protocol = "-1"; cidr_blocks = ["0.0.0.0/0"] }
}

resource "aws_security_group" "internal_alb" {
  name   = "${var.project_name}-internal-alb-sg"
  vpc_id = aws_vpc.main.id
  ingress { from_port = 80; to_port = 80; protocol = "tcp"; security_groups = [aws_security_group.web.id] }
  egress  { from_port = 0;  to_port = 0;  protocol = "-1"; cidr_blocks = ["0.0.0.0/0"] }
}

resource "aws_security_group" "app" {
  name   = "${var.project_name}-app-sg"
  vpc_id = aws_vpc.main.id
  ingress { from_port = 3000; to_port = 3000; protocol = "tcp"; security_groups = [aws_security_group.internal_alb.id] }
  egress  { from_port = 0;    to_port = 0;    protocol = "-1"; cidr_blocks = ["0.0.0.0/0"] }
}

resource "aws_security_group" "db" {
  name   = "${var.project_name}-db-sg"
  vpc_id = aws_vpc.main.id
  ingress { from_port = 3306; to_port = 3306; protocol = "tcp"; security_groups = [aws_security_group.app.id] }
}
```

### modules/database/main.tf

```hcl
resource "aws_db_subnet_group" "main" {
  name       = "${var.project_name}-db-subnet-group"
  subnet_ids = var.db_subnet_ids
}

resource "aws_db_instance" "primary" {
  identifier             = "${var.project_name}-db-primary"
  engine                 = "mysql"
  engine_version         = "8.0"
  instance_class         = var.db_instance_class
  db_name                = var.db_name
  username               = var.db_username  # supplied via tfvars or CI/CD vault
  password               = var.db_password  # sensitive = true; never hardcoded
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [var.db_sg_id]
  multi_az               = true
  storage_type           = "gp3"
  allocated_storage      = 20
  skip_final_snapshot    = false
  final_snapshot_identifier = "${var.project_name}-final-snapshot"
  backup_retention_period   = 7
}

resource "aws_db_instance" "replica" {
  identifier          = "${var.project_name}-db-replica"
  replicate_source_db = aws_db_instance.primary.identifier
  instance_class      = var.db_instance_class
  skip_final_snapshot = true
}
```

### variables.tf

```hcl
variable "aws_region"         { default = "us-east-1" }
variable "project_name"       { default = "3tier-ha" }
variable "vpc_cidr"           { default = "10.0.0.0/16" }
variable "public_subnets"     { default = ["10.0.1.0/24", "10.0.2.0/24"] }
variable "private_subnets"    { default = ["10.0.3.0/24", "10.0.4.0/24"] }
variable "db_subnets"         { default = ["10.0.5.0/24", "10.0.6.0/24"] }
variable "availability_zones" { default = ["us-east-1a", "us-east-1b"] }
variable "ami_id"             { default = "ami-0c02fb55956c7d316" }
variable "key_name"           { description = "Name of the EC2 key pair" }
variable "web_instance_type"  { default = "t3.micro" }
variable "app_instance_type"  { default = "t3.micro" }
variable "db_instance_class"  { default = "db.t3.micro" }
variable "db_name"            { description = "Database name" }
variable "db_username"        { description = "Database admin username" }
variable "db_password"        {
  description = "Database admin password"
  sensitive   = true
}
variable "web_min_size"       { default = 2 }
variable "web_max_size"       { default = 4 }
variable "app_min_size"       { default = 2 }
variable "app_max_size"       { default = 4 }
```

### terraform.tfvars.example

```hcl
# Copy to terraform.tfvars and fill in your own values.
# terraform.tfvars is listed in .gitignore — never commit it.
key_name    = "your-ec2-keypair-name"
db_name     = "appdb"
db_username = "dbadmin"
db_password = "replace-with-a-strong-password"
```

## Deployment Steps

```bash
# 1. Copy and populate vars (do NOT commit terraform.tfvars)
cp terraform.tfvars.example terraform.tfvars

# 2. Initialise Terraform — downloads providers, configures S3 backend
terraform init

# 3. Preview the execution plan — no changes applied yet
terraform plan

# 4. Apply the infrastructure
terraform apply

# 5. Retrieve outputs after a successful apply
terraform output public_alb_dns
terraform output db_endpoint

# 6. Verify health checks on the Public ALB
curl -I http://$(terraform output -raw public_alb_dns)/health
# Expected: HTTP/1.1 200 OK

# 7. Tear down when done
terraform destroy
```

## Security Practices Applied

| Concern | Approach |
|---|---|
| DB credentials | Sensitive Terraform variables — never hardcoded; passed via `terraform.tfvars` (gitignored) or CI/CD secret store |
| AWS credentials | IAM role on CI runner or local `~/.aws/credentials` — never in code |
| App Tier | No public IP; only reachable via Internal ALB |
| DB Tier | Security Group restricts access to App Tier SG on port 3306 only |
| State file | Remote S3 backend with AES-256 encryption and DynamoDB state locking |
| Sensitive output | `sensitive = true` on `db_password` — masked in all plan and apply output |

## Key Concepts Demonstrated

- **Modular Terraform** — network, compute, and database split into independently reusable modules
- **Remote State** — S3 backend with DynamoDB locking for safe team collaboration
- **High Availability** — Multi-AZ deployment spanning two Availability Zones
- **Least-Privilege Security** — Each tier's Security Group only allows traffic from its direct upstream caller
- **Load Balancing** — Public ALB for web tier; Internal ALB for app tier
- **Auto Scaling** — ASG on both tiers with ELB health checks and configurable grace period
- **RDS Multi-AZ** — Synchronous standby with automatic failover, plus a Read Replica for read scaling
- **Credential Safety** — `sensitive = true` on all secret variables; `.gitignore` excludes `terraform.tfvars`

---

**Tools:** Terraform · AWS VPC · EC2 · ALB · Auto Scaling Groups · RDS MySQL · S3 · IAM
