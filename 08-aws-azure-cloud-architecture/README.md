# Project 08 — AWS & Azure Cloud Architecture: Production 3-Tier HA Deployment

## What This Project Does

Deployed the Book Review App (Next.js + Node.js + MySQL) as a production-grade, highly available 3-tier architecture on both AWS and Azure. The goal was to build infrastructure the way it runs in real production environments — with tier isolation, private subnets, load balancers with health checks, database high availability, and security rules enforcing least-privilege access between every layer.

The same architecture is implemented on both platforms to show that cloud concepts are platform-agnostic. The services have different names but the design patterns are identical.

---

## Architecture

```
Internet
    |
[Public ALB / Load Balancer]      <- only entry point from the internet
    |
[Web Tier - Public Subnets]       <- Next.js + Nginx on EC2/VM
    |
[Internal ALB / Internal LB]      <- web tier reaches app tier internally only
    |
[App Tier - Private Subnets]      <- Node.js backend, NO public IP
    |
[DB Tier - Private Subnets]       <- MySQL RDS Multi-AZ, only app tier can reach it
```

Each tier can only receive traffic from the tier directly above it.
The database has no route to the internet.

---

## AWS Implementation

### VPC and Subnet Design

```
VPC CIDR: 10.0.0.0/16

Web Tier (Public):   10.0.1.0/24 us-east-1a    10.0.2.0/24 us-east-1b
App Tier (Private):  10.0.3.0/24 us-east-1a    10.0.4.0/24 us-east-1b
DB Tier (Private):   10.0.5.0/24 us-east-1a    10.0.6.0/24 us-east-1b

Internet Gateway attached to VPC
NAT Gateway in public subnet - private subnets route outbound through it
```

### Security Groups - Least Privilege Chain

```
Public ALB SG:    inbound 80   from 0.0.0.0/0
Web Tier SG:      inbound 80   from Public ALB SG only
Internal ALB SG:  inbound 3001 from Web Tier SG only
App Tier SG:      inbound 3001 from Internal ALB SG only
DB Tier SG:       inbound 3306 from App Tier SG only
```

Nothing can skip a layer. The database only accepts connections from the app servers.

### Load Balancers

**Public ALB** (internet-facing)
- Listener: HTTP:80
- Target group: Web Tier EC2 instances
- Health check: GET / returns 200
- Distributes traffic across both AZs

**Internal ALB** (private - not reachable from internet)
- Listener: HTTP:3001
- Target group: App Tier EC2 instances
- Health check: GET /health returns 200
- Only reachable from Web Tier SG

### RDS MySQL - Multi-AZ + Read Replica

- **Multi-AZ**: standby instance in second AZ, automatic failover if primary fails
- **Read Replica**: separate instance for read-heavy queries, reduces load on primary
- Placed in DB private subnets only
- Security group allows port 3306 from App Tier SG only

### EC2 Deployment

Web Tier EC2s run in public subnets with Nginx proxying to Next.js on port 3000.
App Tier EC2s run in private subnets with Node.js on port 3001 - no public IP assigned.

---

## Azure Implementation

### VNet and Subnet Design

```
VNet CIDR: 10.0.0.0/16

Web Tier (Public):   10.0.1.0/24    10.0.2.0/24
App Tier (Private):  10.0.3.0/24    10.0.4.0/24
DB Tier (Private):   10.0.5.0/24    10.0.6.0/24
```

### NSG Rules

```
Web Tier NSG:  allow inbound 80   from internet
App Tier NSG:  allow inbound 3001 from Web Tier NSG only
DB Tier NSG:   allow inbound 3306 from App Tier NSG only
```

### Load Balancers

**Public Load Balancer** - static frontend IP, backend pool of web VMs, health probe on port 80

**Internal Load Balancer** - private frontend IP, backend pool of app VMs, health probe on port 3001

### Azure Database for MySQL Flexible Server

- Private VNet integration - not publicly accessible
- Read replica enabled
- Firewall rules scoped to App Tier subnet only

---

## Scripts

The `scripts/` folder contains the AWS CLI commands used to provision this architecture step by step - VPC, subnets, security groups, load balancers, EC2 instances, and RDS.

---

## What I Learned

**Private subnets matter** - even if someone discovers an app or DB server IP, there is no route from the internet to reach it. The architecture enforces this at the network layer.

**Security group chaining** - each tier only accepts traffic from the tier directly above it. This is enforced before any application code runs. If the web tier is compromised, the attacker still cannot reach the database because the DB security group only trusts the App Tier SG.

**Public vs internal load balancer** - the public ALB is the front door from the internet. The internal ALB is infrastructure routing between tiers. Nothing external can reach the internal ALB.

**Multi-AZ RDS** - the database keeps running even if an entire availability zone goes down. AWS handles the failover automatically with no manual intervention.

**Cloud concepts transfer** - VPC = VNet, Security Group = NSG, ALB = Azure Load Balancer, RDS = Azure Database for MySQL. Once you understand the pattern, implementing it on either platform is straightforward.

---

## Tools Used

**AWS:** VPC, EC2, ALB (public + internal), RDS MySQL Multi-AZ + Read Replica, Security Groups, NAT Gateway, IAM

**Azure:** VNet, Virtual Machines, Load Balancer (public + internal), MySQL Flexible Server, NSG, RBAC
