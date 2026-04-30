#!/bin/bash
# ============================================================
# 01-setup-vpc.sh -- Provision AWS VPC with public/private subnets
# ============================================================
# Builds the network foundation for the 3-tier architecture:
#   - VPC with a /16 CIDR block (65,536 IP addresses)
#   - 2 public subnets (web tier) across 2 Availability Zones
#   - 2 private subnets (app/db tier) across 2 Availability Zones
#   - Internet Gateway for public internet access
#   - NAT Gateway for outbound-only internet from private subnets
#   - Route tables wired up correctly
#
# Prerequisites:
#   aws configure   (set your AWS credentials and default region)
#
# Usage:
#   chmod +x 01-setup-vpc.sh && ./01-setup-vpc.sh

set -euo pipefail
# -e: exit on error  -u: error on unset vars  -o pipefail: catch errors in pipes

REGION="eu-west-2"
VPC_CIDR="10.0.0.0/16"

echo "==> Creating VPC in region: $REGION"

# -- Create VPC -----------------------------------------------
# A VPC is a logically isolated section of the AWS cloud.
# /16 gives 65,536 IP addresses to carve into subnets.
VPC_ID=$(aws ec2 create-vpc \
  --cidr-block "$VPC_CIDR" \
  --region "$REGION" \
  --query "Vpc.VpcId" \
  --output text)

aws ec2 create-tags --resources "$VPC_ID" \
  --tags Key=Name,Value=epicbook-vpc Key=Project,Value=epicbook

echo "VPC created: $VPC_ID"

# Enable DNS hostnames so EC2 instances get public DNS names
aws ec2 modify-vpc-attribute --vpc-id "$VPC_ID" --enable-dns-hostnames

# -- Public subnets -------------------------------------------
# Two public subnets across two AZs for high availability.
# The ALB requires subnets in at least 2 AZs.
PUBLIC_SUBNET_1=$(aws ec2 create-subnet \
  --vpc-id "$VPC_ID" \
  --cidr-block 10.0.1.0/24 \
  --availability-zone "${REGION}a" \
  --query "Subnet.SubnetId" \
  --output text)

PUBLIC_SUBNET_2=$(aws ec2 create-subnet \
  --vpc-id "$VPC_ID" \
  --cidr-block 10.0.2.0/24 \
  --availability-zone "${REGION}b" \
  --query "Subnet.SubnetId" \
  --output text)

echo "Public subnets: $PUBLIC_SUBNET_1 / $PUBLIC_SUBNET_2"

# -- Private subnets ------------------------------------------
# No direct internet route. App and DB tiers live here.
PRIVATE_SUBNET_1=$(aws ec2 create-subnet \
  --vpc-id "$VPC_ID" \
  --cidr-block 10.0.10.0/24 \
  --availability-zone "${REGION}a" \
  --query "Subnet.SubnetId" \
  --output text)

PRIVATE_SUBNET_2=$(aws ec2 create-subnet \
  --vpc-id "$VPC_ID" \
  --cidr-block 10.0.11.0/24 \
  --availability-zone "${REGION}b" \
  --query "Subnet.SubnetId" \
  --output text)

echo "Private subnets: $PRIVATE_SUBNET_1 / $PRIVATE_SUBNET_2"

# -- Internet Gateway -----------------------------------------
# Allows resources in public subnets to reach the internet.
IGW_ID=$(aws ec2 create-internet-gateway \
  --query "InternetGateway.InternetGatewayId" \
  --output text)

aws ec2 attach-internet-gateway --vpc-id "$VPC_ID" --internet-gateway-id "$IGW_ID"
echo "Internet Gateway: $IGW_ID"

# -- Public route table ---------------------------------------
# Routes 0.0.0.0/0 traffic from public subnets to the Internet Gateway.
PUBLIC_RT=$(aws ec2 create-route-table \
  --vpc-id "$VPC_ID" \
  --query "RouteTable.RouteTableId" \
  --output text)

aws ec2 create-route --route-table-id "$PUBLIC_RT" \
  --destination-cidr-block 0.0.0.0/0 --gateway-id "$IGW_ID"

aws ec2 associate-route-table --subnet-id "$PUBLIC_SUBNET_1" --route-table-id "$PUBLIC_RT"
aws ec2 associate-route-table --subnet-id "$PUBLIC_SUBNET_2" --route-table-id "$PUBLIC_RT"

# -- NAT Gateway ----------------------------------------------
# Private instances can make outbound requests (e.g. apt install)
# without being reachable from the internet.
EIP_ALLOC=$(aws ec2 allocate-address --domain vpc --query "AllocationId" --output text)

NAT_GW=$(aws ec2 create-nat-gateway \
  --subnet-id "$PUBLIC_SUBNET_1" \
  --allocation-id "$EIP_ALLOC" \
  --query "NatGateway.NatGatewayId" \
  --output text)

echo "Waiting for NAT Gateway to become available..."
aws ec2 wait nat-gateway-available --nat-gateway-ids "$NAT_GW"
echo "NAT Gateway ready: $NAT_GW"

# -- Private route table --------------------------------------
PRIVATE_RT=$(aws ec2 create-route-table \
  --vpc-id "$VPC_ID" \
  --query "RouteTable.RouteTableId" \
  --output text)

aws ec2 create-route --route-table-id "$PRIVATE_RT" \
  --destination-cidr-block 0.0.0.0/0 --nat-gateway-id "$NAT_GW"

aws ec2 associate-route-table --subnet-id "$PRIVATE_SUBNET_1" --route-table-id "$PRIVATE_RT"
aws ec2 associate-route-table --subnet-id "$PRIVATE_SUBNET_2" --route-table-id "$PRIVATE_RT"

# -- Save IDs for subsequent scripts --------------------------
cat > vpc-ids.env << EOF
VPC_ID=$VPC_ID
PUBLIC_SUBNET_1=$PUBLIC_SUBNET_1
PUBLIC_SUBNET_2=$PUBLIC_SUBNET_2
PRIVATE_SUBNET_1=$PRIVATE_SUBNET_1
PRIVATE_SUBNET_2=$PRIVATE_SUBNET_2
IGW_ID=$IGW_ID
NAT_GW=$NAT_GW
EOF

echo ""
echo "==> VPC setup complete. IDs saved to vpc-ids.env"
echo "==> Next: run 02-setup-alb.sh to create the Application Load Balancer"
