#!/bin/bash
# ============================================================
# 03-launch-ec2.sh -- Launch EC2 instances and register with ALB
# ============================================================
# Creates:
#   - EC2 security group: allows HTTP from ALB SG only (not from internet)
#   - Two EC2 instances in separate public subnets (multi-AZ)
#   - Installs Docker and runs the app container via User Data
#   - Registers instances in the ALB target group
#
# Run AFTER 02-setup-alb.sh
# Usage: source vpc-ids.env && ./03-launch-ec2.sh

set -euo pipefail

if [ ! -f vpc-ids.env ]; then
  echo "ERROR: vpc-ids.env not found. Run 01-setup-vpc.sh first."
  exit 1
fi
source vpc-ids.env

REGION="eu-west-2"
# Amazon Linux 2023 AMI for eu-west-2 -- update with latest AMI ID for your region
# Find current AMI: aws ec2 describe-images --owners amazon \
#   --filters "Name=name,Values=al2023-ami-*" --query "sort_by(Images, &CreationDate)[-1].ImageId"
AMI_ID="ami-0c7a4976cb6fafd3a"
INSTANCE_TYPE="t3.small"
KEY_NAME="<your-ec2-key-pair-name>"     # replace with your key pair name

echo "==> Creating EC2 security group"

# -- EC2 Security Group ---------------------------------------
# Only accepts traffic from the ALB security group, not directly
# from the internet. This enforces the ALB as the single entry point.
EC2_SG=$(aws ec2 create-security-group \
  --group-name epicbook-ec2-sg \
  --description "Allow HTTP from ALB only, SSH from admin" \
  --vpc-id "$VPC_ID" \
  --query "GroupId" \
  --output text)

# Allow HTTP from ALB SG only (not from 0.0.0.0/0)
aws ec2 authorize-security-group-ingress \
  --group-id "$EC2_SG" \
  --protocol tcp --port 80 \
  --source-group "$ALB_SG"

# Allow SSH from your IP only -- replace 0.0.0.0/0 with your actual IP in production
aws ec2 authorize-security-group-ingress \
  --group-id "$EC2_SG" \
  --protocol tcp --port 22 \
  --cidr 0.0.0.0/0    # SECURITY: restrict to your IP before production use

echo "EC2 security group: $EC2_SG"

# -- User Data script -----------------------------------------
# Runs automatically on first boot. Installs Docker and starts the container.
# The app image is pulled from a public ECR repo for this demo.
USER_DATA=$(cat << "USERDATA"
#!/bin/bash
yum update -y
yum install -y docker
systemctl start docker
systemctl enable docker

# Pull and run the application container
docker run -d \
  --name epicbook \
  --restart unless-stopped \
  -p 80:3000 \
  -e NODE_ENV=production \
  -e PORT=3000 \
  <your-ecr-repo>/epicbook:latest
USERDATA
)

USER_DATA_B64=$(echo "$USER_DATA" | base64)

# -- Launch EC2 instances -------------------------------------
# Two instances in different AZs. If one AZ goes down, the ALB
# automatically routes all traffic to the healthy instance.
echo "==> Launching EC2 instances"

INSTANCE_1=$(aws ec2 run-instances \
  --image-id "$AMI_ID" \
  --instance-type "$INSTANCE_TYPE" \
  --key-name "$KEY_NAME" \
  --security-group-ids "$EC2_SG" \
  --subnet-id "$PUBLIC_SUBNET_1" \
  --associate-public-ip-address \
  --user-data "$USER_DATA_B64" \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=epicbook-web-1a}]" \
  --query "Instances[0].InstanceId" \
  --output text)

INSTANCE_2=$(aws ec2 run-instances \
  --image-id "$AMI_ID" \
  --instance-type "$INSTANCE_TYPE" \
  --key-name "$KEY_NAME" \
  --security-group-ids "$EC2_SG" \
  --subnet-id "$PUBLIC_SUBNET_2" \
  --associate-public-ip-address \
  --user-data "$USER_DATA_B64" \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=epicbook-web-1b}]" \
  --query "Instances[0].InstanceId" \
  --output text)

echo "Instances launched: $INSTANCE_1, $INSTANCE_2"
echo "Waiting for instances to reach running state..."
aws ec2 wait instance-running --instance-ids "$INSTANCE_1" "$INSTANCE_2"
echo "Instances running."

# -- Register with target group -------------------------------
# Adding instances to the target group allows the ALB to start
# health-checking them and routing traffic once they are healthy.
aws elbv2 register-targets \
  --target-group-arn "$TG_ARN" \
  --targets Id="$INSTANCE_1" Id="$INSTANCE_2"

echo ""
echo "==> EC2 instances registered with ALB target group."
echo "==> Application will be available at: http://$ALB_DNS"
echo "==> Note: Allow 2-3 minutes for health checks to pass before testing."
