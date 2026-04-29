# Project 08 — AWS & Azure Cloud Architecture: Production 3-Tier with High Availability

## Overview

Designed and deployed a production-grade 3-tier web application architecture across both AWS and Azure, demonstrating multi-cloud proficiency. The AWS deployment features a custom VPC with public/private subnet segregation, Application Load Balancers, Auto Scaling Groups, Multi-AZ RDS, and CloudWatch monitoring. The Azure deployment mirrors the architecture using Virtual Machines, Network Security Groups, and Azure Load Balancer.

## AWS Architecture

```
                        Internet
                           |
                    [Route 53 DNS]
                           |
                    [Internet Gateway]
                           |
              ┌────────────┴────────────┐
              |                         |
    [Public Subnet AZ-1]      [Public Subnet AZ-2]
       Web Tier EC2               Web Tier EC2
              |                         |
              └────────[Public ALB]─────┘
                    (health checks /health)
                           |
              ┌────────────┴────────────┐
              |                         |
   [Private Subnet AZ-1]    [Private Subnet AZ-2]
      App Tier EC2              App Tier EC2
      (NO public IP)            (NO public IP)
              |                         |
              └───────[Internal ALB]────┘
                    (health checks /health)
                           |
         ┌─────────────────┴──────────────────┐
         |                                     |
  [DB Subnet AZ-1]                    [DB Subnet AZ-2]
  RDS MySQL Primary                   RDS MySQL Standby
  (Multi-AZ Active)                   (Automatic Failover)
         |
  [Read Replica]

Security Groups (Least Privilege):
  sg_alb:          0.0.0.0/0        → port 80
  sg_web:          sg_alb           → port 80
  sg_internal_alb: sg_web           → port 80
  sg_app:          sg_internal_alb  → port 3000
  sg_db:           sg_app           → port 3306 (App Tier only)
```

## Azure Architecture

```
                    Internet
                        |
               [Azure Load Balancer]
                        |
          ┌─────────────┴──────────────┐
          |                            |
   [VM — Web Tier 1]           [VM — Web Tier 2]
   Ubuntu + Nginx               Ubuntu + Nginx
          |                            |
    [NSG: allow 80]             [NSG: allow 80]
          |                            |
          └─────────[Internal LB]──────┘
                          |
          ┌───────────────┴───────────────┐
          |                               |
   [VM — App Tier 1]             [VM — App Tier 2]
   Ubuntu + Node.js              Ubuntu + Node.js
   [NSG: port 3000 from          [NSG: port 3000 from
    internal LB only]             internal LB only]
                          |
                    [Azure MySQL Flexible Server]
                    [NSG: port 3306 from app tier only]
```

## AWS Deployment Steps

### 1. VPC and Networking

```bash
# Create VPC
aws ec2 create-vpc --cidr-block 10.0.0.0/16 \
  --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=prod-vpc}]'

# Create and attach Internet Gateway
aws ec2 create-internet-gateway \
  --tag-specifications 'ResourceType=internet-gateway,Tags=[{Key=Name,Value=prod-igw}]'
aws ec2 attach-internet-gateway --vpc-id <vpc-id> --internet-gateway-id <igw-id>

# Create public subnets (Web Tier)
aws ec2 create-subnet --vpc-id <vpc-id> --cidr-block 10.0.1.0/24 \
  --availability-zone us-east-1a \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=public-1a}]'
aws ec2 create-subnet --vpc-id <vpc-id> --cidr-block 10.0.2.0/24 \
  --availability-zone us-east-1b \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=public-1b}]'

# Create private subnets (App Tier)
aws ec2 create-subnet --vpc-id <vpc-id> --cidr-block 10.0.3.0/24 \
  --availability-zone us-east-1a \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=private-1a}]'
aws ec2 create-subnet --vpc-id <vpc-id> --cidr-block 10.0.4.0/24 \
  --availability-zone us-east-1b \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=private-1b}]'

# Create DB subnets
aws ec2 create-subnet --vpc-id <vpc-id> --cidr-block 10.0.5.0/24 \
  --availability-zone us-east-1a \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=db-1a}]'
aws ec2 create-subnet --vpc-id <vpc-id> --cidr-block 10.0.6.0/24 \
  --availability-zone us-east-1b \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=db-1b}]'

# NAT Gateway for private subnets
aws ec2 allocate-address --domain vpc
aws ec2 create-nat-gateway --subnet-id <public-subnet-id> --allocation-id <eip-alloc-id>

# Route tables
aws ec2 create-route-table --vpc-id <vpc-id> \
  --tag-specifications 'ResourceType=route-table,Tags=[{Key=Name,Value=public-rt}]'
aws ec2 create-route --route-table-id <public-rt-id> \
  --destination-cidr-block 0.0.0.0/0 --gateway-id <igw-id>

aws ec2 create-route-table --vpc-id <vpc-id> \
  --tag-specifications 'ResourceType=route-table,Tags=[{Key=Name,Value=private-rt}]'
aws ec2 create-route --route-table-id <private-rt-id> \
  --destination-cidr-block 0.0.0.0/0 --nat-gateway-id <nat-id>
```

### 2. Security Groups

```bash
# ALB Security Group — public internet access
aws ec2 create-security-group --group-name sg-alb --description "ALB SG" --vpc-id <vpc-id>
aws ec2 authorize-security-group-ingress --group-id <sg-alb-id> \
  --protocol tcp --port 80 --cidr 0.0.0.0/0

# Web Tier — allow traffic from ALB only
aws ec2 create-security-group --group-name sg-web --description "Web Tier SG" --vpc-id <vpc-id>
aws ec2 authorize-security-group-ingress --group-id <sg-web-id> \
  --protocol tcp --port 80 --source-group <sg-alb-id>

# Internal ALB — allow traffic from Web Tier only
aws ec2 create-security-group --group-name sg-internal-alb --description "Internal ALB SG" --vpc-id <vpc-id>
aws ec2 authorize-security-group-ingress --group-id <sg-ialb-id> \
  --protocol tcp --port 80 --source-group <sg-web-id>

# App Tier — allow traffic from Internal ALB only
aws ec2 create-security-group --group-name sg-app --description "App Tier SG" --vpc-id <vpc-id>
aws ec2 authorize-security-group-ingress --group-id <sg-app-id> \
  --protocol tcp --port 3000 --source-group <sg-ialb-id>

# DB Tier — allow ONLY App Tier on port 3306
aws ec2 create-security-group --group-name sg-db --description "DB Tier SG" --vpc-id <vpc-id>
aws ec2 authorize-security-group-ingress --group-id <sg-db-id> \
  --protocol tcp --port 3306 --source-group <sg-app-id>
```

### 3. Application Load Balancers

```bash
# Public ALB (internet-facing)
aws elbv2 create-load-balancer \
  --name prod-public-alb \
  --subnets <public-subnet-1a> <public-subnet-1b> \
  --security-groups <sg-alb-id> \
  --scheme internet-facing \
  --type application

aws elbv2 create-target-group \
  --name prod-web-tg \
  --protocol HTTP --port 80 \
  --vpc-id <vpc-id> \
  --health-check-path /health \
  --health-check-interval-seconds 30 \
  --healthy-threshold-count 2 \
  --unhealthy-threshold-count 2

# Internal ALB (private)
aws elbv2 create-load-balancer \
  --name prod-internal-alb \
  --subnets <private-subnet-1a> <private-subnet-1b> \
  --security-groups <sg-ialb-id> \
  --scheme internal \
  --type application

aws elbv2 create-target-group \
  --name prod-app-tg \
  --protocol HTTP --port 3000 \
  --vpc-id <vpc-id> \
  --health-check-path /health
```

### 4. Auto Scaling Groups

```bash
# Web Tier Launch Template
aws ec2 create-launch-template \
  --launch-template-name web-tier-lt \
  --launch-template-data '{
    "ImageId": "ami-0c02fb55956c7d316",
    "InstanceType": "t3.micro",
    "SecurityGroupIds": ["<sg-web-id>"],
    "UserData": "<base64-encoded-userdata>"
  }'

# Web Tier ASG (public subnets)
aws autoscaling create-auto-scaling-group \
  --auto-scaling-group-name web-tier-asg \
  --launch-template "LaunchTemplateName=web-tier-lt,Version=$Latest" \
  --min-size 2 --max-size 4 --desired-capacity 2 \
  --vpc-zone-identifier "<public-subnet-1a>,<public-subnet-1b>" \
  --target-group-arns <web-tg-arn> \
  --health-check-type ELB \
  --health-check-grace-period 300

# App Tier Launch Template — NO public IP
aws ec2 create-launch-template \
  --launch-template-name app-tier-lt \
  --launch-template-data '{
    "ImageId": "ami-0c02fb55956c7d316",
    "InstanceType": "t3.micro",
    "SecurityGroupIds": ["<sg-app-id>"],
    "NetworkInterfaces": [{"AssociatePublicIpAddress": false, "DeviceIndex": 0}]
  }'

# App Tier ASG (private subnets)
aws autoscaling create-auto-scaling-group \
  --auto-scaling-group-name app-tier-asg \
  --launch-template "LaunchTemplateName=app-tier-lt,Version=$Latest" \
  --min-size 2 --max-size 4 --desired-capacity 2 \
  --vpc-zone-identifier "<private-subnet-1a>,<private-subnet-1b>" \
  --target-group-arns <app-tg-arn> \
  --health-check-type ELB \
  --health-check-grace-period 300
```

### 5. RDS MySQL Multi-AZ

```bash
# DB Subnet Group
aws rds create-db-subnet-group \
  --db-subnet-group-name prod-db-subnet-group \
  --db-subnet-group-description "Production DB subnet group" \
  --subnet-ids <db-subnet-1a> <db-subnet-1b>

# RDS Primary with Multi-AZ
# Credentials are passed via environment variables or AWS Secrets Manager — never hardcoded
aws rds create-db-instance \
  --db-instance-identifier prod-mysql-primary \
  --db-instance-class db.t3.micro \
  --engine mysql --engine-version 8.0 \
  --master-username "${DB_ADMIN_USER}" \
  --master-user-password "${DB_ADMIN_PASSWORD}" \
  --db-name appdb \
  --db-subnet-group-name prod-db-subnet-group \
  --vpc-security-group-ids <sg-db-id> \
  --multi-az \
  --storage-type gp3 --allocated-storage 20 \
  --backup-retention-period 7 \
  --no-publicly-accessible

# Read Replica
aws rds create-db-instance-read-replica \
  --db-instance-identifier prod-mysql-replica \
  --source-db-instance-identifier prod-mysql-primary \
  --db-instance-class db.t3.micro
```

### 6. CloudWatch Monitoring & Alarms

```bash
# Scale-out alarm: CPU > 70% for 10 minutes
aws cloudwatch put-metric-alarm \
  --alarm-name web-cpu-high \
  --alarm-description "Scale out when CPU exceeds 70% for 10 minutes" \
  --metric-name CPUUtilization \
  --namespace AWS/EC2 \
  --statistic Average \
  --period 300 --threshold 70 \
  --comparison-operator GreaterThanThreshold \
  --dimensions Name=AutoScalingGroupName,Value=web-tier-asg \
  --evaluation-periods 2 \
  --alarm-actions <scale-out-policy-arn>

# ALB unhealthy host alarm
aws cloudwatch put-metric-alarm \
  --alarm-name alb-unhealthy-hosts \
  --metric-name UnHealthyHostCount \
  --namespace AWS/ApplicationELB \
  --statistic Average \
  --period 60 --threshold 1 \
  --comparison-operator GreaterThanOrEqualToThreshold \
  --evaluation-periods 1 \
  --alarm-actions <sns-ops-topic-arn>
```

## Azure Deployment Steps

### 1. Resource Group and Virtual Network

```bash
# Authenticate and select subscription
az login
az account set --subscription "<your-subscription-id>"

# Resource Group
az group create --name prod-rg --location eastus

# Virtual Network and subnets
az network vnet create \
  --resource-group prod-rg --name prod-vnet \
  --address-prefix 10.0.0.0/16

az network vnet subnet create \
  --resource-group prod-rg --vnet-name prod-vnet \
  --name web-subnet --address-prefix 10.0.1.0/24

az network vnet subnet create \
  --resource-group prod-rg --vnet-name prod-vnet \
  --name app-subnet --address-prefix 10.0.2.0/24

az network vnet subnet create \
  --resource-group prod-rg --vnet-name prod-vnet \
  --name db-subnet --address-prefix 10.0.3.0/24
```

### 2. Network Security Groups

```bash
# Web Tier NSG
az network nsg create --resource-group prod-rg --name web-nsg
az network nsg rule create --resource-group prod-rg --nsg-name web-nsg \
  --name AllowHTTP --protocol tcp --direction Inbound --priority 100 \
  --source-address-prefix '*' --source-port-range '*' \
  --destination-port-range 80 --access Allow

# App Tier NSG — allow only from web subnet
az network nsg create --resource-group prod-rg --name app-nsg
az network nsg rule create --resource-group prod-rg --nsg-name app-nsg \
  --name AllowFromWeb --protocol tcp --direction Inbound --priority 100 \
  --source-address-prefix 10.0.1.0/24 --source-port-range '*' \
  --destination-port-range 3000 --access Allow

# DB NSG — allow only from app subnet
az network nsg create --resource-group prod-rg --name db-nsg
az network nsg rule create --resource-group prod-rg --nsg-name db-nsg \
  --name AllowFromApp --protocol tcp --direction Inbound --priority 100 \
  --source-address-prefix 10.0.2.0/24 --source-port-range '*' \
  --destination-port-range 3306 --access Allow
```

### 3. VMs and Load Balancer

```bash
# Create Web Tier VMs (SSH key authentication — no password auth)
for i in 1 2; do
  az vm create \
    --resource-group prod-rg \
    --name web-vm-$i \
    --image Ubuntu2204 \
    --size Standard_B1s \
    --subnet web-subnet \
    --vnet-name prod-vnet \
    --nsg web-nsg \
    --admin-username azureuser \
    --ssh-key-values ~/.ssh/id_rsa.pub \
    --custom-data cloud-init-web.txt
done

# Azure Load Balancer
az network lb create \
  --resource-group prod-rg --name prod-lb \
  --sku Standard \
  --frontend-ip-name frontend \
  --backend-pool-name web-backend

az network lb probe create \
  --resource-group prod-rg --lb-name prod-lb \
  --name health-probe --protocol Http --port 80 --path /health

az network lb rule create \
  --resource-group prod-rg --lb-name prod-lb \
  --name http-rule --protocol tcp \
  --frontend-port 80 --backend-port 80 \
  --frontend-ip-name frontend \
  --backend-pool-name web-backend \
  --probe-name health-probe
```

## Health Check Verification

```bash
# AWS — check ALB target health
aws elbv2 describe-target-health --target-group-arn <web-tg-arn>
# Expected: TargetHealth.State = "healthy"

# AWS — test public ALB endpoint
curl -I http://<public-alb-dns>/health
# Expected: HTTP/1.1 200 OK

# Azure — check LB probe status
az network lb show --resource-group prod-rg --name prod-lb --query "probes"

# Azure — test endpoint
curl -I http://<azure-lb-public-ip>/health
# Expected: HTTP/1.1 200 OK
```

## Security Practices Applied

| Concern | Approach |
|---|---|
| DB credentials | Environment variables (`${DB_ADMIN_USER}`, `${DB_ADMIN_PASSWORD}`) set in the shell or CI/CD secret store — never hardcoded in commands or scripts |
| Azure subscription ID | Referenced as `<your-subscription-id>` — stored in CI/CD secret variable |
| App Tier VMs | No public IP — only reachable via Internal Load Balancer |
| DB Tier SG / NSG | Port 3306 / 3306 restricted to App Tier source only |
| VM authentication | SSH key-based — password authentication disabled |
| AWS credentials | IAM role on CI runner — no access keys in code |

## Key Concepts Demonstrated

- **Multi-Cloud** — Equivalent production deployments on both AWS and Azure
- **High Availability** — Multi-AZ across two Availability Zones with automatic RDS failover
- **Load Balancing** — Public ALB (web tier) + Internal ALB (app tier) on AWS; Standard Azure LB
- **Auto Scaling** — ASGs with ELB health checks and CPU-based CloudWatch alarms
- **Least-Privilege Security** — Dedicated SG/NSG per tier; traffic flows only between adjacent tiers
- **Health Checks** — ALB and Azure LB probes on `/health` endpoint
- **Monitoring & Alerting** — CloudWatch alarms for CPU utilisation, unhealthy host count, SNS notifications

---

**Tools:** AWS VPC · EC2 · ALB · Auto Scaling · RDS MySQL · CloudWatch · Route 53 · Azure VMs · Azure Load Balancer · NSG · Azure MySQL Flexible Server
