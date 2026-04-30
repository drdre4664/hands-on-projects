#!/bin/bash
# ============================================================
# 02-setup-alb.sh -- Create Application Load Balancer + Target Group
# ============================================================
# Creates:
#   - Security Group: allows HTTP/HTTPS inbound to the ALB
#   - Application Load Balancer spanning both public subnets
#   - Target Group: registers EC2 instances for health-checked routing
#   - Listener: forwards port 80 traffic to the target group
#
# Run AFTER 01-setup-vpc.sh
# Usage: source vpc-ids.env && ./02-setup-alb.sh

set -euo pipefail

# Load VPC IDs from the previous script
if [ ! -f vpc-ids.env ]; then
  echo "ERROR: vpc-ids.env not found. Run 01-setup-vpc.sh first."
  exit 1
fi
source vpc-ids.env

REGION="eu-west-2"

echo "==> Creating ALB security group"

# -- ALB Security Group ---------------------------------------
# The ALB needs its own security group that allows HTTP/HTTPS
# from anywhere. EC2 instances will only allow traffic FROM this SG.
ALB_SG=$(aws ec2 create-security-group \
  --group-name epicbook-alb-sg \
  --description "Allow HTTP/HTTPS inbound to ALB" \
  --vpc-id "$VPC_ID" \
  --query "GroupId" \
  --output text)

# Allow HTTP from anywhere
aws ec2 authorize-security-group-ingress \
  --group-id "$ALB_SG" \
  --protocol tcp --port 80 --cidr 0.0.0.0/0

# Allow HTTPS from anywhere (for future TLS certificate)
aws ec2 authorize-security-group-ingress \
  --group-id "$ALB_SG" \
  --protocol tcp --port 443 --cidr 0.0.0.0/0

echo "ALB security group: $ALB_SG"

# -- Create Application Load Balancer -------------------------
# internet-facing = has a public DNS name and routes from the internet.
# Spans both public subnets for multi-AZ high availability.
ALB_ARN=$(aws elbv2 create-load-balancer \
  --name epicbook-alb \
  --type application \
  --scheme internet-facing \
  --subnets "$PUBLIC_SUBNET_1" "$PUBLIC_SUBNET_2" \
  --security-groups "$ALB_SG" \
  --query "LoadBalancers[0].LoadBalancerArn" \
  --output text)

ALB_DNS=$(aws elbv2 describe-load-balancers \
  --load-balancer-arns "$ALB_ARN" \
  --query "LoadBalancers[0].DNSName" \
  --output text)

echo "ALB created: $ALB_DNS"

# -- Target Group ---------------------------------------------
# The target group holds the EC2 instances that the ALB routes to.
# Health check on /health ensures only healthy instances receive traffic.
TG_ARN=$(aws elbv2 create-target-group \
  --name epicbook-tg \
  --protocol HTTP \
  --port 80 \
  --vpc-id "$VPC_ID" \
  --health-check-path "/health" \
  --health-check-interval-seconds 30 \
  --healthy-threshold-count 2 \
  --unhealthy-threshold-count 3 \
  --query "TargetGroups[0].TargetGroupArn" \
  --output text)

echo "Target Group: $TG_ARN"

# -- Listener -------------------------------------------------
# The listener watches for HTTP connections on port 80 and
# forwards them to the target group using round-robin.
aws elbv2 create-listener \
  --load-balancer-arn "$ALB_ARN" \
  --protocol HTTP \
  --port 80 \
  --default-actions Type=forward,TargetGroupArn="$TG_ARN"

echo "Listener created on port 80"

# -- Append IDs to env file -----------------------------------
cat >> vpc-ids.env << EOF
ALB_ARN=$ALB_ARN
ALB_DNS=$ALB_DNS
ALB_SG=$ALB_SG
TG_ARN=$TG_ARN
EOF

echo ""
echo "==> ALB setup complete."
echo "==> ALB DNS: $ALB_DNS"
echo "==> Next: run 03-launch-ec2.sh to launch EC2 instances"
