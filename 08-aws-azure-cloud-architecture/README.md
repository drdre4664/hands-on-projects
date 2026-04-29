# AWS & Azure Cloud Architecture — Production 3-Tier with High Availability

## Overview

Designed and deployed a production-grade 3-tier web application architecture across AWS and Azure, demonstrating multi-cloud proficiency. The AWS deployment features a custom VPC with public/private subnet segregation, Application Load Balancer, Auto Scaling Groups, Multi-AZ RDS, and CloudWatch monitoring. The Azure deployment uses Virtual Machines, Network Security Groups, and Azure Load Balancer.

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
  [Read Replica]  ← separate read replica for scaling

Security Groups (Least Privilege):
  sg_alb:          0.0.0.0/0 → port 80
  sg_web:          sg_alb → port 80
  sg_internal_alb: sg_web → port 80
  sg_app:          sg_internal_alb → port 3000
  sg_db:           sg_app → port 3306  ← ONLY app tier
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
    [NSG: allow 80/443]         [NSG: allow 80/443]
          |                            |
          └─────────[Internal LB]──────┘
                          |
          ┌───────────────┴───────────────┐
          |                               |
   [VM — App Tier 1]             [VM — App Tier 2]
   Ubuntu + Node.js              Ubuntu + Node.js
          |                               |
    [NSG: allow 3000                [NSG: allow 3000
     from internal LB only]         from internal LB only]
                          |
                    [Azure MySQL]
                  (Flexible Server)
                    [NSG: allow 3306
                    from app tier only]
```

## AWS Deployment Steps

### 1. VPC and Networking

```bash
# Create VPC
aws ec2 create-vpc --cidr-block 10.0.0.0/16 --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=prod-vpc}]'

# Create Internet Gateway
aws ec2 create-internet-gateway --tag-specifications 'ResourceType=internet-gateway,Tags=[{Key=Name,Value=prod-igw}]'
aws ec2 attach-internet-gateway --vpc-id vpc-XXXXX --internet-gateway-id igw-XXXXX

# Create public subnets (Web Tier)
aws ec2 create-subnet --vpc-id vpc-XXXXX --cidr-block 10.0.1.0/24 --availability-zone us-east-1a --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=public-1a}]'
aws ec2 create-subnet --vpc-id vpc-XXXXX --cidr-block 10.0.2.0/24 --availability-zone us-east-1b --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=public-1b}]'

# Create private subnets (App Tier)
aws ec2 create-subnet --vpc-id vpc-XXXXX --cidr-block 10.0.3.0/24 --availability-zone us-east-1a --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=private-1a}]'
aws ec2 create-subnet --vpc-id vpc-XXXXX --cidr-block 10.0.4.0/24 --availability-zone us-east-1b --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=private-1b}]'

# Create DB subnets
aws ec2 create-subnet --vpc-id vpc-XXXXX --cidr-block 10.0.5.0/24 --availability-zone us-east-1a --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=db-1a}]'
aws ec2 create-subnet --vpc-id vpc-XXXXX --cidr-block 10.0.6.0/24 --availability-zone us-east-1b --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=db-1b}]'

# NAT Gateway for private subnets
aws ec2 allocate-address --domain vpc
aws ec2 create-nat-gateway --subnet-id subnet-PUBLIC-1a --allocation-id eipalloc-XXXXX

# Route tables
aws ec2 create-route-table --vpc-id vpc-XXXXX --tag-specifications 'ResourceType=route-table,Tags=[{Key=Name,Value=public-rt}]'
aws ec2 create-route --route-table-id rtb-XXXXX --destination-cidr-block 0.0.0.0/0 --gateway-id igw-XXXXX

aws ec2 create-route-table --vpc-id vpc-XXXXX --tag-specifications 'ResourceType=route-table,Tags=[{Key=Name,Value=private-rt}]'
aws ec2 create-route --route-table-id rtb-YYYY --destination-cidr-block 0.0.0.0/0 --nat-gateway-id nat-XXXXX
```

### 2. Security Groups

```bash
# ALB Security Group
aws ec2 create-security-group --group-name sg-alb --description "ALB SG" --vpc-id vpc-XXXXX
aws ec2 authorize-security-group-ingress --group-id sg-ALB --protocol tcp --port 80 --cidr 0.0.0.0/0

# Web Tier Security Group (only from ALB)
aws ec2 create-security-group --group-name sg-web --description "Web Tier SG" --vpc-id vpc-XXXXX
aws ec2 authorize-security-group-ingress --group-id sg-WEB --protocol tcp --port 80 --source-group sg-ALB

# Internal ALB Security Group
aws ec2 create-security-group --group-name sg-internal-alb --description "Internal ALB SG" --vpc-id vpc-XXXXX
aws ec2 authorize-security-group-ingress --group-id sg-IALB --protocol tcp --port 80 --source-group sg-WEB

# App Tier Security Group (only from Internal ALB)
aws ec2 create-security-group --group-name sg-app --description "App Tier SG" --vpc-id vpc-XXXXX
aws ec2 authorize-security-group-ingress --group-id sg-APP --protocol tcp --port 3000 --source-group sg-IALB

# DB Tier Security Group (ONLY from App Tier)
aws ec2 create-security-group --group-name sg-db --description "DB Tier SG" --vpc-id vpc-XXXXX
aws ec2 authorize-security-group-ingress --group-id sg-DB --protocol tcp --port 3306 --source-group sg-APP
```

### 3. Application Load Balancers

```bash
# Public ALB
aws elbv2 create-load-balancer   --name prod-public-alb   --subnets subnet-PUBLIC-1a subnet-PUBLIC-1b   --security-groups sg-ALB   --scheme internet-facing   --type application

# Public ALB Target Group
aws elbv2 create-target-group   --name prod-web-tg   --protocol HTTP   --port 80   --vpc-id vpc-XXXXX   --health-check-path /health   --health-check-interval-seconds 30   --healthy-threshold-count 2   --unhealthy-threshold-count 2

# Internal ALB
aws elbv2 create-load-balancer   --name prod-internal-alb   --subnets subnet-PRIVATE-1a subnet-PRIVATE-1b   --security-groups sg-IALB   --scheme internal   --type application

# Internal ALB Target Group
aws elbv2 create-target-group   --name prod-app-tg   --protocol HTTP   --port 3000   --vpc-id vpc-XXXXX   --health-check-path /health
```

### 4. Auto Scaling Groups

```bash
# Web Tier Launch Template
aws ec2 create-launch-template   --launch-template-name web-tier-lt   --version-description "Web Tier v1"   --launch-template-data '{
    "ImageId": "ami-0c02fb55956c7d316",
    "InstanceType": "t3.micro",
    "SecurityGroupIds": ["sg-WEB"],
    "UserData": "IyEvYmluL2Jhc2gKeXVtIHVwZGF0ZSAteQp5dW0gaW5zdGFsbCAteSBuZ2lueApzeXN0ZW1jdGwgc3RhcnQgbmdpbngK"
  }'

# Web Tier ASG
aws autoscaling create-auto-scaling-group   --auto-scaling-group-name web-tier-asg   --launch-template LaunchTemplateName=web-tier-lt,Version='$Latest'   --min-size 2   --max-size 4   --desired-capacity 2   --vpc-zone-identifier "subnet-PUBLIC-1a,subnet-PUBLIC-1b"   --target-group-arns arn:aws:elasticloadbalancing:us-east-1:ACCOUNT:targetgroup/prod-web-tg/XXXXX   --health-check-type ELB   --health-check-grace-period 300

# App Tier Launch Template (NO public IP)
aws ec2 create-launch-template   --launch-template-name app-tier-lt   --launch-template-data '{
    "ImageId": "ami-0c02fb55956c7d316",
    "InstanceType": "t3.micro",
    "SecurityGroupIds": ["sg-APP"],
    "NetworkInterfaces": [{"AssociatePublicIpAddress": false, "DeviceIndex": 0}]
  }'

# App Tier ASG
aws autoscaling create-auto-scaling-group   --auto-scaling-group-name app-tier-asg   --launch-template LaunchTemplateName=app-tier-lt,Version='$Latest'   --min-size 2   --max-size 4   --desired-capacity 2   --vpc-zone-identifier "subnet-PRIVATE-1a,subnet-PRIVATE-1b"   --target-group-arns arn:aws:elasticloadbalancing:us-east-1:ACCOUNT:targetgroup/prod-app-tg/XXXXX   --health-check-type ELB   --health-check-grace-period 300
```

### 5. RDS MySQL Multi-AZ

```bash
# Create DB Subnet Group
aws rds create-db-subnet-group   --db-subnet-group-name prod-db-subnet-group   --db-subnet-group-description "Production DB subnet group"   --subnet-ids subnet-DB-1a subnet-DB-1b

# Create RDS Primary (Multi-AZ)
aws rds create-db-instance   --db-instance-identifier prod-mysql-primary   --db-instance-class db.t3.micro   --engine mysql   --engine-version 8.0   --master-username admin   --master-user-password SecurePass123!   --db-name appdb   --db-subnet-group-name prod-db-subnet-group   --vpc-security-group-ids sg-DB   --multi-az   --storage-type gp3   --allocated-storage 20   --backup-retention-period 7   --no-publicly-accessible

# Create Read Replica
aws rds create-db-instance-read-replica   --db-instance-identifier prod-mysql-replica   --source-db-instance-identifier prod-mysql-primary   --db-instance-class db.t3.micro
```

### 6. CloudWatch Monitoring

```bash
# CPU alarm for auto scaling
aws cloudwatch put-metric-alarm   --alarm-name web-cpu-high   --alarm-description "Scale out when CPU > 70%"   --metric-name CPUUtilization   --namespace AWS/EC2   --statistic Average   --period 300   --threshold 70   --comparison-operator GreaterThanThreshold   --dimensions Name=AutoScalingGroupName,Value=web-tier-asg   --evaluation-periods 2   --alarm-actions arn:aws:autoscaling:us-east-1:ACCOUNT:scalingPolicy:XXXXX

# ALB unhealthy host alarm
aws cloudwatch put-metric-alarm   --alarm-name alb-unhealthy-hosts   --metric-name UnHealthyHostCount   --namespace AWS/ApplicationELB   --statistic Average   --period 60   --threshold 1   --comparison-operator GreaterThanOrEqualToThreshold   --evaluation-periods 1   --alarm-actions arn:aws:sns:us-east-1:ACCOUNT:ops-alerts
```

## Azure Deployment Steps

### 1. Resource Group and VNet

```bash
# Login and set subscription
az login
az account set --subscription "SUBSCRIPTION_ID"

# Create Resource Group
az group create --name prod-rg --location eastus

# Create Virtual Network
az network vnet create   --resource-group prod-rg   --name prod-vnet   --address-prefix 10.0.0.0/16

# Create subnets
az network vnet subnet create --resource-group prod-rg --vnet-name prod-vnet --name web-subnet --address-prefix 10.0.1.0/24
az network vnet subnet create --resource-group prod-rg --vnet-name prod-vnet --name app-subnet --address-prefix 10.0.2.0/24
az network vnet subnet create --resource-group prod-rg --vnet-name prod-vnet --name db-subnet  --address-prefix 10.0.3.0/24
```

### 2. NSG Rules

```bash
# Web Tier NSG
az network nsg create --resource-group prod-rg --name web-nsg
az network nsg rule create --resource-group prod-rg --nsg-name web-nsg --name AllowHTTP   --protocol tcp --direction Inbound --priority 100 --source-address-prefix '*'   --source-port-range '*' --destination-port-range 80 --access Allow

# App Tier NSG (allow only from web tier subnet)
az network nsg create --resource-group prod-rg --name app-nsg
az network nsg rule create --resource-group prod-rg --nsg-name app-nsg --name AllowFromWeb   --protocol tcp --direction Inbound --priority 100 --source-address-prefix 10.0.1.0/24   --source-port-range '*' --destination-port-range 3000 --access Allow

# DB NSG (allow only from app tier subnet)
az network nsg create --resource-group prod-rg --name db-nsg
az network nsg rule create --resource-group prod-rg --nsg-name db-nsg --name AllowFromApp   --protocol tcp --direction Inbound --priority 100 --source-address-prefix 10.0.2.0/24   --source-port-range '*' --destination-port-range 3306 --access Allow
```

### 3. VMs and Load Balancer

```bash
# Create Web Tier VMs
for i in 1 2; do
  az vm create     --resource-group prod-rg     --name web-vm-$i     --image Ubuntu2204     --size Standard_B1s     --subnet web-subnet     --vnet-name prod-vnet     --nsg web-nsg     --admin-username azureuser     --ssh-key-values ~/.ssh/id_rsa.pub     --custom-data cloud-init-web.txt
done

# Create Azure Load Balancer
az network lb create   --resource-group prod-rg   --name prod-lb   --sku Standard   --frontend-ip-name frontend   --backend-pool-name web-backend

az network lb probe create   --resource-group prod-rg   --lb-name prod-lb   --name health-probe   --protocol Http   --port 80   --path /health

az network lb rule create   --resource-group prod-rg   --lb-name prod-lb   --name http-rule   --protocol tcp   --frontend-port 80   --backend-port 80   --frontend-ip-name frontend   --backend-pool-name web-backend   --probe-name health-probe
```

## Health Check Verification

```bash
# AWS — verify ALB health checks
aws elbv2 describe-target-health --target-group-arn arn:aws:elasticloadbalancing:REGION:ACCOUNT:targetgroup/prod-web-tg/XXXXX
# Expected: TargetHealth.State = "healthy"

# AWS — test public ALB endpoint
curl -I http://prod-public-alb-XXXXX.us-east-1.elb.amazonaws.com/health
# Expected: HTTP/1.1 200 OK

# Azure — verify LB probe
az network lb show --resource-group prod-rg --name prod-lb --query "probes"

# Azure — test endpoint
curl -I http://PUBLIC_IP/health
# Expected: HTTP/1.1 200 OK
```

## Key Concepts Demonstrated

- **Multi-Cloud** — Production deployments on both AWS and Azure
- **High Availability** — Multi-AZ across 2 Availability Zones with automatic failover
- **Load Balancing** — Public ALB (web tier) + Internal ALB (app tier) on AWS; Azure LB
- **Auto Scaling** — ASGs with ELB health checks scale based on CPU/traffic
- **Security** — Least-privilege Security Groups / NSGs; App Tier has no public IP
- **Database HA** — RDS Multi-AZ with Read Replica; Azure MySQL Flexible Server
- **Health Checks** — ALB health checks on /health endpoint, CloudWatch alarms
- **Monitoring** — CloudWatch alarms for CPU, unhealthy hosts, SNS notifications

---

**Tools:** AWS VPC · EC2 · ALB · Auto Scaling · RDS MySQL · CloudWatch · Route 53 · Azure VMs · Azure Load Balancer · NSG · Azure MySQL
