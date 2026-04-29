# Terraform IaaC — AWS 3-Tier Architecture with High Availability

## Overview

Provisioned a production-grade, highly available 3-tier architecture on AWS using Terraform Infrastructure as Code. The deployment includes a custom VPC with 6 subnets across 2 Availability Zones, public and internal Application Load Balancers, Auto Scaling Groups, and a Multi-AZ RDS MySQL database with a Read Replica.

## Architecture

```
Internet
    |
[Internet Gateway]
    |
[Public ALB] — sg_alb (port 80 inbound from 0.0.0.0/0)
    |
[Web Tier EC2 — Public Subnets AZ-1 & AZ-2]
    |   sg_web: allows 80 from sg_alb only
    |
[Internal ALB] — sg_internal_alb (port 80 from sg_web)
    |
[App Tier EC2 — Private Subnets AZ-1 & AZ-2]
    |   sg_app: allows 3000 from sg_internal_alb only
    |   NO public IP assigned
    |
[RDS MySQL Multi-AZ + Read Replica]
    sg_db: allows 3306 from sg_app ONLY
    [DB Subnets AZ-1 & AZ-2 — isolated tier]
```

## Assignment Objectives

- Create a custom VPC with 6 subnets: 2 public (web tier), 2 private (app tier), 2 DB subnets
- Deploy Web Tier EC2 instances in public subnets — NO Elastic IPs
- Deploy App Tier EC2 instances in private subnets — NO public IP
- Configure Public ALB for web tier with health checks
- Configure Internal ALB for app tier with health checks
- Set up RDS MySQL with Multi-AZ deployment and a Read Replica
- Implement Security Groups with least-privilege access between tiers
- DB Tier SG allows ONLY App Tier SG on port 3306

## Project Structure

```
06-terraform-iaac/
├── main.tf
├── variables.tf
├── outputs.tf
├── terraform.tfvars
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
    bucket = "devops-terraform-state-bucket"
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
  username               = var.db_username
  password               = var.db_password
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
variable "key_name"           {}
variable "web_instance_type"  { default = "t3.micro" }
variable "app_instance_type"  { default = "t3.micro" }
variable "db_instance_class"  { default = "db.t3.micro" }
variable "db_name"            { default = "appdb" }
variable "db_username"        { default = "admin" }
variable "db_password"        { sensitive = true }
variable "web_min_size"       { default = 2 }
variable "web_max_size"       { default = 4 }
variable "app_min_size"       { default = 2 }
variable "app_max_size"       { default = 4 }
```

## Deployment Steps

```bash
# 1. Initialize Terraform
terraform init

# 2. Review plan
terraform plan -var="key_name=my-keypair" -var="db_password=SecurePass123!"

# 3. Apply
terraform apply -var="key_name=my-keypair" -var="db_password=SecurePass123!" -auto-approve

# 4. Get outputs
terraform output public_alb_dns
terraform output db_endpoint

# 5. Destroy
terraform destroy -auto-approve
```

## Key Concepts Demonstrated

- **Modular Terraform** — network, compute, and database as reusable modules
- **Remote State** — S3 backend with state locking
- **High Availability** — Multi-AZ deployment across 2 Availability Zones
- **Security** — Least-privilege Security Groups; App Tier has no public IP
- **Load Balancing** — Public ALB for web tier, Internal ALB for app tier
- **Auto Scaling** — ASG for both tiers with ELB health checks
- **RDS Multi-AZ** — Automatic failover + Read Replica for read scaling

---

**Tools:** Terraform · AWS VPC · EC2 · ALB · Auto Scaling · RDS MySQL · S3
