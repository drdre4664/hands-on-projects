# Project 08 — AWS & Azure Cloud Architecture: Production 3-Tier with High Availability

## What This Project Does

This project designs and builds a production-grade, highly available 3-tier web application infrastructure on both AWS and Azure, demonstrating multi-cloud proficiency. The same architectural principles — tier separation, least-privilege networking, load balancing, auto scaling, and database high availability — are applied on both platforms, using each platform's native tools.

On AWS, the infrastructure is built using the CLI to understand exactly what each service does and how the components connect. On Azure, the equivalent architecture is built with the Azure CLI. Seeing both side-by-side deepens understanding of cloud concepts that are universal, even when the tooling and terminology differ.

## Core Principles Applied

Before looking at any commands, it helps to understand the design decisions behind the architecture:

**Why 6 subnets?** Three tiers (web, app, database) × two Availability Zones = six subnets. Spreading each tier across two AZs means if one data centre has an outage, traffic automatically shifts to the other AZ. The application keeps running.

**Why no public IP on the App Tier?** The application servers do not need to be reachable directly from the internet. They only need to receive traffic from the Internal ALB. Removing public IPs eliminates an entire class of attack surface.

**Why Security Groups instead of IP-based rules?** If an EC2 instance's IP changes (after a restart, scaling event, etc.), IP-based firewall rules break. Security Group-based rules reference the SG itself, so they automatically apply to any new instance that joins the group.

---

## AWS Architecture

```
Internet
    |
[Route 53]  ← DNS — routes domain to the Public ALB
    |
[Internet Gateway]
    |
[Public ALB]
    Health check: GET /health → must return 200
    |
    ├──[Web EC2 — Public Subnet us-east-1a]
    └──[Web EC2 — Public Subnet us-east-1b]
         Security Group: allows :80 from ALB SG only
    |
[Internal ALB]  ← private, not reachable from internet
    Health check: GET /health → must return 200
    |
    ├──[App EC2 — Private Subnet us-east-1a]  ← no public IP
    └──[App EC2 — Private Subnet us-east-1b]  ← no public IP
         Security Group: allows :3000 from Internal ALB SG only
    |
    ├──[RDS MySQL Primary — DB Subnet us-east-1a]  ← Multi-AZ active
    └──[RDS MySQL Standby — DB Subnet us-east-1b]  ← auto failover
         Security Group: allows :3306 from App SG ONLY
    |
[Read Replica]  ← async copy of primary — for read-heavy query offloading
```

## Azure Architecture

```
Internet
    |
[Azure Load Balancer]  ← Standard SKU, with health probe on /health
    |
    ├──[VM web-vm-1 — web-subnet 10.0.1.x]  Ubuntu + Nginx
    └──[VM web-vm-2 — web-subnet 10.0.1.x]  Ubuntu + Nginx
         NSG: allows :80 from * (internet)
    |
[Internal Load Balancer]
    |
    ├──[VM app-vm-1 — app-subnet 10.0.2.x]  Ubuntu + Node.js
    └──[VM app-vm-2 — app-subnet 10.0.2.x]  Ubuntu + Node.js
         NSG: allows :3000 from 10.0.1.0/24 (web subnet) only
    |
[Azure MySQL Flexible Server — db-subnet 10.0.3.x]
    NSG: allows :3306 from 10.0.2.0/24 (app subnet) only
```

---

## AWS Deployment Steps

### Step 1 — Create the VPC and Subnets

**Why a custom VPC?** The default VPC has everything in public subnets. A custom VPC lets us precisely control which subnets are public (have internet access) and which are private (isolated). This is mandatory for a proper 3-tier architecture.

```bash
# Create the VPC — the private network that will contain all our resources
aws ec2 create-vpc --cidr-block 10.0.0.0/16 \
  --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=prod-vpc}]'
# Note the VPC ID returned — you will need it for subsequent commands

# Attach an Internet Gateway — this is what gives public subnets internet access
aws ec2 create-internet-gateway \
  --tag-specifications 'ResourceType=internet-gateway,Tags=[{Key=Name,Value=prod-igw}]'
aws ec2 attach-internet-gateway --vpc-id <vpc-id> --internet-gateway-id <igw-id>

# Create two public subnets — one per AZ, for the web tier
aws ec2 create-subnet --vpc-id <vpc-id> --cidr-block 10.0.1.0/24 --availability-zone us-east-1a \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=public-1a}]'
aws ec2 create-subnet --vpc-id <vpc-id> --cidr-block 10.0.2.0/24 --availability-zone us-east-1b \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=public-1b}]'

# Create two private subnets — one per AZ, for the app tier
aws ec2 create-subnet --vpc-id <vpc-id> --cidr-block 10.0.3.0/24 --availability-zone us-east-1a \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=private-1a}]'
aws ec2 create-subnet --vpc-id <vpc-id> --cidr-block 10.0.4.0/24 --availability-zone us-east-1b \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=private-1b}]'

# Create two DB subnets — one per AZ, for RDS (required for Multi-AZ)
aws ec2 create-subnet --vpc-id <vpc-id> --cidr-block 10.0.5.0/24 --availability-zone us-east-1a \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=db-1a}]'
aws ec2 create-subnet --vpc-id <vpc-id> --cidr-block 10.0.6.0/24 --availability-zone us-east-1b \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=db-1b}]'
```

### Step 2 — Route Tables and NAT Gateway

**Why a NAT Gateway?** Private subnet instances (app tier) have no internet route by default — which is what we want for security. But they still need to reach the internet to download packages and pull code. A NAT Gateway in a public subnet lets them do this: outbound connections work, but no inbound connections from the internet are possible.

```bash
# Allocate an Elastic IP for the NAT Gateway
aws ec2 allocate-address --domain vpc

# Create the NAT Gateway in a public subnet (it needs internet access itself)
aws ec2 create-nat-gateway --subnet-id <public-subnet-1a> --allocation-id <eip-alloc-id>

# Public route table: routes 0.0.0.0/0 (all internet traffic) through the Internet Gateway
aws ec2 create-route-table --vpc-id <vpc-id> \
  --tag-specifications 'ResourceType=route-table,Tags=[{Key=Name,Value=public-rt}]'
aws ec2 create-route --route-table-id <public-rt-id> \
  --destination-cidr-block 0.0.0.0/0 --gateway-id <igw-id>

# Private route table: routes internet traffic through the NAT Gateway (outbound only)
aws ec2 create-route-table --vpc-id <vpc-id> \
  --tag-specifications 'ResourceType=route-table,Tags=[{Key=Name,Value=private-rt}]'
aws ec2 create-route --route-table-id <private-rt-id> \
  --destination-cidr-block 0.0.0.0/0 --nat-gateway-id <nat-id>
```

### Step 3 — Security Groups

**Why chain Security Groups?** Each SG references the one above it as the source. The DB SG allows traffic from `sg-app`, not from any IP range. This means only EC2 instances that are members of `sg-app` can reach the database — not just anything with the right IP.

```bash
# ALB SG: the only SG that accepts traffic from the public internet
aws ec2 create-security-group --group-name sg-alb --description "Public ALB" --vpc-id <vpc-id>
aws ec2 authorize-security-group-ingress --group-id <sg-alb-id> \
  --protocol tcp --port 80 --cidr 0.0.0.0/0

# Web Tier SG: only accepts traffic from the ALB SG (not from the internet directly)
aws ec2 create-security-group --group-name sg-web --description "Web Tier" --vpc-id <vpc-id>
aws ec2 authorize-security-group-ingress --group-id <sg-web-id> \
  --protocol tcp --port 80 --source-group <sg-alb-id>

# Internal ALB SG: only accepts traffic from the web tier
aws ec2 create-security-group --group-name sg-internal-alb --description "Internal ALB" --vpc-id <vpc-id>
aws ec2 authorize-security-group-ingress --group-id <sg-ialb-id> \
  --protocol tcp --port 80 --source-group <sg-web-id>

# App Tier SG: only accepts traffic from the internal ALB
aws ec2 create-security-group --group-name sg-app --description "App Tier" --vpc-id <vpc-id>
aws ec2 authorize-security-group-ingress --group-id <sg-app-id> \
  --protocol tcp --port 3000 --source-group <sg-ialb-id>

# DB Tier SG: only accepts MySQL traffic from the app tier — nothing else
aws ec2 create-security-group --group-name sg-db --description "DB Tier" --vpc-id <vpc-id>
aws ec2 authorize-security-group-ingress --group-id <sg-db-id> \
  --protocol tcp --port 3306 --source-group <sg-app-id>
```

### Step 4 — Application Load Balancers

**Why two load balancers?** The public ALB handles traffic between the internet and the web tier. The internal ALB handles traffic between the web tier and the app tier. Using an Internal ALB for the app tier means web servers never connect directly to app servers — the internal LB provides an abstraction layer, enabling health checking, scaling, and rolling updates on the app tier without the web tier knowing.

```bash
# Public ALB — internet-facing
aws elbv2 create-load-balancer --name prod-public-alb \
  --subnets <public-subnet-1a> <public-subnet-1b> \
  --security-groups <sg-alb-id> \
  --scheme internet-facing --type application

# Target group for the web tier with health checks
aws elbv2 create-target-group --name prod-web-tg \
  --protocol HTTP --port 80 --vpc-id <vpc-id> \
  --health-check-path /health \
  --health-check-interval-seconds 30 \
  --healthy-threshold-count 2 \
  --unhealthy-threshold-count 2
# The ALB will only route traffic to instances that return 200 on /health

# Internal ALB — private, not reachable from internet
aws elbv2 create-load-balancer --name prod-internal-alb \
  --subnets <private-subnet-1a> <private-subnet-1b> \
  --security-groups <sg-ialb-id> \
  --scheme internal --type application

aws elbv2 create-target-group --name prod-app-tg \
  --protocol HTTP --port 3000 --vpc-id <vpc-id> \
  --health-check-path /health
```

### Step 5 — Auto Scaling Groups

**Why Auto Scaling?** Fixed-size fleets waste money when traffic is low and fall over when traffic spikes. ASGs automatically add instances when load increases (scale out) and remove them when load drops (scale in), keeping cost and capacity aligned with actual demand.

```bash
# Web Tier Launch Template — defines what each new web server looks like
aws ec2 create-launch-template --launch-template-name web-tier-lt \
  --launch-template-data '{
    "ImageId": "ami-0c02fb55956c7d316",
    "InstanceType": "t3.micro",
    "SecurityGroupIds": ["<sg-web-id>"]
  }'

# Web Tier ASG — maintains 2-4 instances across the two public subnets
aws autoscaling create-auto-scaling-group \
  --auto-scaling-group-name web-tier-asg \
  --launch-template "LaunchTemplateName=web-tier-lt,Version=$Latest" \
  --min-size 2 --max-size 4 --desired-capacity 2 \
  --vpc-zone-identifier "<public-subnet-1a>,<public-subnet-1b>" \
  --target-group-arns <web-tg-arn> \
  --health-check-type ELB \        # use ALB health checks, not just EC2 status
  --health-check-grace-period 300   # give new instances 5 minutes to start up

# App Tier Launch Template — NO public IP assigned
aws ec2 create-launch-template --launch-template-name app-tier-lt \
  --launch-template-data '{
    "ImageId": "ami-0c02fb55956c7d316",
    "InstanceType": "t3.micro",
    "SecurityGroupIds": ["<sg-app-id>"],
    "NetworkInterfaces": [{"AssociatePublicIpAddress": false, "DeviceIndex": 0}]
  }'

# App Tier ASG — same pattern, but in private subnets
aws autoscaling create-auto-scaling-group \
  --auto-scaling-group-name app-tier-asg \
  --launch-template "LaunchTemplateName=app-tier-lt,Version=$Latest" \
  --min-size 2 --max-size 4 --desired-capacity 2 \
  --vpc-zone-identifier "<private-subnet-1a>,<private-subnet-1b>" \
  --target-group-arns <app-tg-arn> \
  --health-check-type ELB \
  --health-check-grace-period 300
```

### Step 6 — RDS MySQL Multi-AZ

**Why Multi-AZ?** A single-AZ database is a single point of failure. With Multi-AZ, AWS maintains a synchronous replica in a second AZ. If the primary instance fails (hardware failure, network issue, AZ outage), AWS automatically promotes the standby to primary — typically in under two minutes, with no manual intervention.

```bash
# DB Subnet Group — tells RDS which subnets to use (must span at least 2 AZs)
aws rds create-db-subnet-group \
  --db-subnet-group-name prod-db-subnet-group \
  --db-subnet-group-description "Production DB subnet group" \
  --subnet-ids <db-subnet-1a> <db-subnet-1b>

# Create the primary RDS instance with Multi-AZ enabled
# Credentials come from environment variables — never hardcoded in scripts
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

# Create a Read Replica for offloading read-heavy queries
aws rds create-db-instance-read-replica \
  --db-instance-identifier prod-mysql-replica \
  --source-db-instance-identifier prod-mysql-primary \
  --db-instance-class db.t3.micro
```

### Step 7 — CloudWatch Monitoring

**Why CloudWatch alarms?** Without monitoring, you only find out the application is struggling when users complain. CloudWatch alarms proactively detect high CPU, unhealthy hosts, and other issues — and can trigger Auto Scaling or send notifications to the operations team automatically.

```bash
# Alarm: scale out the web ASG when average CPU exceeds 70% for 10 minutes
aws cloudwatch put-metric-alarm \
  --alarm-name web-cpu-high \
  --alarm-description "Scale out when CPU exceeds 70% for 10 minutes" \
  --metric-name CPUUtilization --namespace AWS/EC2 \
  --statistic Average --period 300 --threshold 70 \
  --comparison-operator GreaterThanThreshold \
  --dimensions Name=AutoScalingGroupName,Value=web-tier-asg \
  --evaluation-periods 2 \
  --alarm-actions <scale-out-policy-arn>

# Alarm: alert the ops team if any ALB target becomes unhealthy
aws cloudwatch put-metric-alarm \
  --alarm-name alb-unhealthy-hosts \
  --metric-name UnHealthyHostCount --namespace AWS/ApplicationELB \
  --statistic Average --period 60 --threshold 1 \
  --comparison-operator GreaterThanOrEqualToThreshold \
  --evaluation-periods 1 \
  --alarm-actions <sns-ops-topic-arn>
```

---

## Azure Deployment Steps

### Step 1 — Resource Group and Virtual Network

**Why a Resource Group?** All Azure resources must belong to a Resource Group — a logical container that makes it easy to manage, monitor, and delete related resources together. Deleting the Resource Group deletes everything in it.

```bash
az login
az account set --subscription "<your-subscription-id>"

# Create the Resource Group
az group create --name prod-rg --location eastus

# Create the VNet with a /16 address space
az network vnet create --resource-group prod-rg --name prod-vnet \
  --address-prefix 10.0.0.0/16

# Three subnets — one per tier
az network vnet subnet create --resource-group prod-rg --vnet-name prod-vnet \
  --name web-subnet --address-prefix 10.0.1.0/24

az network vnet subnet create --resource-group prod-rg --vnet-name prod-vnet \
  --name app-subnet --address-prefix 10.0.2.0/24

az network vnet subnet create --resource-group prod-rg --vnet-name prod-vnet \
  --name db-subnet --address-prefix 10.0.3.0/24
```

### Step 2 — Network Security Groups

**Why NSGs instead of SGs?** Azure uses NSGs (Network Security Groups) for the same purpose as AWS Security Groups. The key difference is that Azure NSGs use subnet-level and NIC-level rules, whereas AWS SGs are attached to individual instances. The principle is the same: only allow traffic from the tier directly above.

```bash
# Web NSG: allow HTTP from anywhere
az network nsg create --resource-group prod-rg --name web-nsg
az network nsg rule create --resource-group prod-rg --nsg-name web-nsg \
  --name AllowHTTP --protocol tcp --direction Inbound --priority 100 \
  --source-address-prefix '*' --destination-port-range 80 --access Allow

# App NSG: only allow traffic from the web subnet
az network nsg create --resource-group prod-rg --name app-nsg
az network nsg rule create --resource-group prod-rg --nsg-name app-nsg \
  --name AllowFromWeb --protocol tcp --direction Inbound --priority 100 \
  --source-address-prefix 10.0.1.0/24 --destination-port-range 3000 --access Allow

# DB NSG: only allow MySQL traffic from the app subnet
az network nsg create --resource-group prod-rg --name db-nsg
az network nsg rule create --resource-group prod-rg --nsg-name db-nsg \
  --name AllowFromApp --protocol tcp --direction Inbound --priority 100 \
  --source-address-prefix 10.0.2.0/24 --destination-port-range 3306 --access Allow
```

### Step 3 — Web Tier VMs and Load Balancer

```bash
# Create two web tier VMs using SSH key authentication
for i in 1 2; do
  az vm create \
    --resource-group prod-rg --name web-vm-$i \
    --image Ubuntu2204 --size Standard_B1s \
    --subnet web-subnet --vnet-name prod-vnet --nsg web-nsg \
    --admin-username azureuser \
    --ssh-key-values ~/.ssh/id_rsa.pub \
    --custom-data cloud-init-web.txt
done

# Create the Azure Load Balancer
az network lb create --resource-group prod-rg --name prod-lb \
  --sku Standard \
  --frontend-ip-name frontend --backend-pool-name web-backend

# Add a health probe — the LB will only send traffic to healthy VMs
az network lb probe create --resource-group prod-rg --lb-name prod-lb \
  --name health-probe --protocol Http --port 80 --path /health

# Create a load balancing rule to forward port 80 to the backend pool
az network lb rule create --resource-group prod-rg --lb-name prod-lb \
  --name http-rule --protocol tcp \
  --frontend-port 80 --backend-port 80 \
  --frontend-ip-name frontend --backend-pool-name web-backend \
  --probe-name health-probe
```

---

## Verification

```bash
# AWS: check that the ALB target group shows healthy targets
aws elbv2 describe-target-health --target-group-arn <web-tg-arn>
# Expected: TargetHealth.State = "healthy" for all targets

# AWS: hit the health endpoint directly through the public ALB
curl -I http://<public-alb-dns>/health
# Expected: HTTP/1.1 200 OK

# Azure: check the load balancer health probe status
az network lb show --resource-group prod-rg --name prod-lb --query "probes"

# Azure: hit the endpoint through the load balancer
curl -I http://<azure-lb-public-ip>/health
# Expected: HTTP/1.1 200 OK
```

---

## What I Learned

- **Multi-AZ is not optional in production.** A single-AZ setup is a single point of failure. Spreading resources across two AZs costs roughly double but provides continuity when one AZ has issues.
- **The Internal ALB pattern** decouples the web tier from the app tier. The web tier never needs to know the private IPs of app servers — it just calls the internal load balancer DNS name. Scaling or replacing app servers is invisible to the web tier.
- **Security Group chaining** (SG references SG as source) is more robust than IP-based rules. It works correctly even as instances are replaced during scaling events.
- **CloudWatch + Auto Scaling together** create a self-managing infrastructure. CPU spikes trigger scale-out automatically; traffic drops trigger scale-in. No human needs to watch dashboards.
- **AWS and Azure are equivalent at the architectural level.** VPC ≈ VNet. Security Group ≈ NSG. ALB ≈ Azure Load Balancer. RDS Multi-AZ ≈ Azure MySQL with zone redundancy. The concepts transfer between platforms.

---

**Tools Used:** AWS VPC · EC2 · Application Load Balancer · Auto Scaling · RDS MySQL · CloudWatch · Route 53 · Azure VMs · Azure Load Balancer · NSG · Azure MySQL Flexible Server
