#!/bin/bash
# Script to deploy HunyuanVideo to AWS using CloudFormation

set -e

# Default values
AWS_REGION="us-west-1"
STACK_NAME="hunyuan-video"
INSTANCE_TYPE="g4dn.xlarge"
KEY_NAME=""
VPC_ID=""
SUBNET_ID=""
SOURCE_CIDR_SSH="0.0.0.0/0"
SOURCE_CIDR_WEB="0.0.0.0/0"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --region)
      AWS_REGION="$2"
      shift 2
      ;;
    --stack-name)
      STACK_NAME="$2"
      shift 2
      ;;
    --instance-type)
      INSTANCE_TYPE="$2"
      shift 2
      ;;
    --key-name)
      KEY_NAME="$2"
      shift 2
      ;;
    --vpc-id)
      VPC_ID="$2"
      shift 2
      ;;
    --subnet-id)
      SUBNET_ID="$2"
      shift 2
      ;;
    --ssh-cidr)
      SOURCE_CIDR_SSH="$2"
      shift 2
      ;;
    --web-cidr)
      SOURCE_CIDR_WEB="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

# Check required parameters
if [ -z "$KEY_NAME" ] || [ -z "$VPC_ID" ] || [ -z "$SUBNET_ID" ]; then
  echo "Error: Missing required parameters."
  echo "Usage: $0 --key-name KEY_NAME --vpc-id VPC_ID --subnet-id SUBNET_ID [--region AWS_REGION] [--stack-name STACK_NAME] [--instance-type INSTANCE_TYPE] [--ssh-cidr SOURCE_CIDR_SSH] [--web-cidr SOURCE_CIDR_WEB]"
  exit 1
fi

# Print configuration
echo "=== Deploying HunyuanVideo to AWS using CloudFormation ==="
echo "Stack Name: $STACK_NAME"
echo "AWS Region: $AWS_REGION"
echo "Instance Type: $INSTANCE_TYPE"
echo "Key Name: $KEY_NAME"
echo "VPC ID: $VPC_ID"
echo "Subnet ID: $SUBNET_ID"
echo "SSH CIDR: $SOURCE_CIDR_SSH"
echo "Web CIDR: $SOURCE_CIDR_WEB"

# Deploy the CloudFormation stack
echo "Deploying CloudFormation stack..."
aws cloudformation deploy \
  --template-file "$(dirname "$0")/cloudformation.yaml" \
  --stack-name "$STACK_NAME" \
  --parameter-overrides \
    InstanceType="$INSTANCE_TYPE" \
    KeyName="$KEY_NAME" \
    VpcId="$VPC_ID" \
    SubnetId="$SUBNET_ID" \
    SourceCidrForSSH="$SOURCE_CIDR_SSH" \
    SourceCidrForWeb="$SOURCE_CIDR_WEB" \
  --capabilities CAPABILITY_IAM \
  --region "$AWS_REGION"

# Get stack outputs
echo "Getting stack outputs..."
OUTPUTS=$(aws cloudformation describe-stacks \
  --stack-name "$STACK_NAME" \
  --region "$AWS_REGION" \
  --query "Stacks[0].Outputs" \
  --output json)

# Extract and display relevant outputs
INSTANCE_ID=$(echo "$OUTPUTS" | jq -r '.[] | select(.OutputKey=="InstanceId") | .OutputValue')
PUBLIC_IP=$(echo "$OUTPUTS" | jq -r '.[] | select(.OutputKey=="PublicIP") | .OutputValue')
WEBSITE_URL=$(echo "$OUTPUTS" | jq -r '.[] | select(.OutputKey=="WebsiteURL") | .OutputValue')
GRADIO_APP_URL=$(echo "$OUTPUTS" | jq -r '.[] | select(.OutputKey=="GradioAppURL") | .OutputValue')
SSH_COMMAND=$(echo "$OUTPUTS" | jq -r '.[] | select(.OutputKey=="SSHCommand") | .OutputValue')

echo "Deployment completed successfully!"
echo "Instance ID: $INSTANCE_ID"
echo "Public IP: $PUBLIC_IP"
echo "Status Page URL: $WEBSITE_URL"
echo "Gradio App URL: $GRADIO_APP_URL"
echo "SSH Command: $SSH_COMMAND"
echo "Note: It may take 10-15 minutes for the application to initialize completely."
echo "To delete the stack when done, run: aws cloudformation delete-stack --stack-name $STACK_NAME --region $AWS_REGION"
