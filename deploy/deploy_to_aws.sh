#!/bin/bash
# Script to deploy the HunyuanVideo application to AWS EC2

set -e

# Default values
INSTANCE_TYPE="g4dn.xlarge"
AWS_REGION="us-west-1"
KEY_NAME=""
SECURITY_GROUP_ID=""
SUBNET_ID=""
AMI_ID=""  # Will be set automatically based on region

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --instance-type)
      INSTANCE_TYPE="$2"
      shift 2
      ;;
    --region)
      AWS_REGION="$2"
      shift 2
      ;;
    --key-name)
      KEY_NAME="$2"
      shift 2
      ;;
    --security-group)
      SECURITY_GROUP_ID="$2"
      shift 2
      ;;
    --subnet)
      SUBNET_ID="$2"
      shift 2
      ;;
    --ami-id)
      AMI_ID="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

# Check required parameters
if [ -z "$KEY_NAME" ] || [ -z "$SECURITY_GROUP_ID" ] || [ -z "$SUBNET_ID" ]; then
  echo "Error: Missing required parameters."
  echo "Usage: $0 --key-name KEY_NAME --security-group SECURITY_GROUP_ID --subnet SUBNET_ID [--instance-type INSTANCE_TYPE] [--region AWS_REGION] [--ami-id AMI_ID]"
  exit 1
fi

# Print configuration
echo "=== Deploying HunyuanVideo to AWS EC2 ==="
echo "Instance Type: $INSTANCE_TYPE"
echo "AWS Region: $AWS_REGION"

# Get the latest Ubuntu 22.04 AMI ID for the specified region if not provided
if [ -z "$AMI_ID" ]; then
  echo "Getting latest Ubuntu 22.04 AMI ID for region ${AWS_REGION}..."
  AMI_ID=$(aws ec2 describe-images \
    --region "$AWS_REGION" \
    --owners 099720109477 \
    --filters "Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*" \
    --query "sort_by(Images, &CreationDate)[-1].ImageId" \
    --output text)
  
  if [ -z "$AMI_ID" ]; then
    echo "Error: Failed to get AMI ID. Please specify it manually with --ami-id."
    exit 1
  fi
fi

echo "AMI ID: $AMI_ID"

# Check if instance type is GPU-enabled
if [[ "$INSTANCE_TYPE" == *"g"* ]] || [[ "$INSTANCE_TYPE" == *"p"* ]]; then
  IS_GPU=true
  echo "Using GPU-enabled instance type."
else
  IS_GPU=false
  echo "WARNING: Using non-GPU instance type. This application requires GPU for optimal performance."
  read -p "Do you want to continue? (y/n) " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Deployment aborted."
    exit 1
  fi
fi

# Create a temporary directory for deployment files
TEMP_DIR=$(mktemp -d)
echo "Creating deployment package in $TEMP_DIR..."

# Copy necessary files to the temporary directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

cp -r "$PROJECT_DIR"/* "$TEMP_DIR"
cd "$TEMP_DIR"

# Create user data script for instance initialization
echo "Creating user data script..."
USER_DATA=$(cat <<EOF
#!/bin/bash
# User data script to set up the HunyuanVideo application on EC2

# Update system packages
apt-get update
apt-get upgrade -y

# Install necessary packages
apt-get install -y git unzip

# Clone the repository
mkdir -p /home/ubuntu/hunyuan-video
cd /home/ubuntu/hunyuan-video

# Download the deployment package
aws s3 cp s3://BUCKET_NAME/hunyuan-video-deployment.zip .
unzip hunyuan-video-deployment.zip
rm hunyuan-video-deployment.zip

# Make scripts executable
chmod +x deploy/setup.sh
chmod +x deploy/build_and_run.sh

# Run setup script
deploy/setup.sh

# Create a script to run the application after reboot
cat > /home/ubuntu/run_hunyuan.sh <<EOL
#!/bin/bash
cd /home/ubuntu/hunyuan-video
deploy/build_and_run.sh
EOL

chmod +x /home/ubuntu/run_hunyuan.sh

# Add to crontab to run after reboot
(crontab -l 2>/dev/null; echo "@reboot /home/ubuntu/run_hunyuan.sh") | crontab -

# Set ownership
chown -R ubuntu:ubuntu /home/ubuntu/hunyuan-video
chown ubuntu:ubuntu /home/ubuntu/run_hunyuan.sh

# Run the application
su - ubuntu -c "/home/ubuntu/run_hunyuan.sh"

# Create a simple status page
cat > /home/ubuntu/status.html <<EOL
<!DOCTYPE html>
<html>
<head>
    <title>HunyuanVideo Application</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; line-height: 1.6; }
        h1 { color: #333; }
        .container { max-width: 800px; margin: 0 auto; }
        .button { display: inline-block; background-color: #4CAF50; color: white; padding: 10px 20px; text-decoration: none; border-radius: 4px; }
    </style>
</head>
<body>
    <div class="container">
        <h1>HunyuanVideo Application</h1>
        <p>The Gradio application is running on this instance.</p>
        <p><a class="button" href="http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):8081">Open Gradio App</a></p>
    </div>
</body>
</html>
EOL

chown ubuntu:ubuntu /home/ubuntu/status.html

# Install a simple web server to serve the status page
apt-get install -y nginx
cat > /etc/nginx/sites-available/default <<EOL
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    root /home/ubuntu;
    index status.html;
    server_name _;
    location / {
        try_files \$uri \$uri/ =404;
    }
}
EOL

systemctl restart nginx
EOF
)

# Create a zip file of the deployment package
echo "Creating deployment package..."
zip -r hunyuan-video-deployment.zip .

# Create an S3 bucket for deployment files if it doesn't exist
BUCKET_NAME="hunyuan-video-deployment-$(date +%s)"
echo "Creating S3 bucket: $BUCKET_NAME..."
aws s3 mb s3://$BUCKET_NAME --region "$AWS_REGION" || true

# Upload the deployment package to S3
echo "Uploading deployment package to S3..."
aws s3 cp hunyuan-video-deployment.zip s3://$BUCKET_NAME/

# Replace the bucket name in the user data script
USER_DATA=${USER_DATA//BUCKET_NAME/$BUCKET_NAME}

# Encode user data in base64
if [[ "$OSTYPE" == "darwin"* ]]; then
  # macOS version of base64 doesn't support -w flag
  USER_DATA_BASE64=$(echo "$USER_DATA" | base64)
else
  # Linux version of base64
  USER_DATA_BASE64=$(echo "$USER_DATA" | base64 -w 0)
fi

# Create IAM role for EC2 instance to access S3
ROLE_NAME="HunyuanVideoEC2Role"
POLICY_NAME="HunyuanVideoS3Access"

# Check if the role already exists
ROLE_EXISTS=$(aws iam get-role --role-name "$ROLE_NAME" 2>/dev/null || echo "false")
if [ "$ROLE_EXISTS" == "false" ]; then
  echo "Creating IAM role: $ROLE_NAME..."
  
  # Create trust policy document
  cat > trust-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

  # Create role
  aws iam create-role --role-name "$ROLE_NAME" --assume-role-policy-document file://trust-policy.json

  # Create policy document
  cat > policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject"
      ],
      "Resource": "arn:aws:s3:::$BUCKET_NAME/*"
    }
  ]
}
EOF

  # Create policy
  aws iam create-policy --policy-name "$POLICY_NAME" --policy-document file://policy.json

  # Attach policy to role
  POLICY_ARN=$(aws iam list-policies --query "Policies[?PolicyName=='$POLICY_NAME'].Arn" --output text)
  aws iam attach-role-policy --role-name "$ROLE_NAME" --policy-arn "$POLICY_ARN"

  # Create instance profile and add role to it
  aws iam create-instance-profile --instance-profile-name "$ROLE_NAME"
  aws iam add-role-to-instance-profile --instance-profile-name "$ROLE_NAME" --role-name "$ROLE_NAME"
  
  # Wait for the instance profile to be available
  echo "Waiting for instance profile to be available..."
  sleep 10
fi

# Get the instance profile ARN
INSTANCE_PROFILE_ARN=$(aws iam get-instance-profile --instance-profile-name "$ROLE_NAME" --query "InstanceProfile.Arn" --output text)

# Launch the EC2 instance
echo "Launching EC2 instance..."
INSTANCE_ID=$(aws ec2 run-instances \
  --image-id "$AMI_ID" \
  --instance-type "$INSTANCE_TYPE" \
  --key-name "$KEY_NAME" \
  --security-group-ids "$SECURITY_GROUP_ID" \
  --subnet-id "$SUBNET_ID" \
  --user-data "$USER_DATA_BASE64" \
  --iam-instance-profile "Name=$ROLE_NAME" \
  --block-device-mappings "[{\"DeviceName\":\"/dev/sda1\",\"Ebs\":{\"VolumeSize\":100,\"VolumeType\":\"gp3\",\"DeleteOnTermination\":true}}]" \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=HunyuanVideo},{Key=Project,Value=HunyuanVideo}]" \
  --region "$AWS_REGION" \
  --query "Instances[0].InstanceId" \
  --output text)

echo "Instance created with ID: $INSTANCE_ID"

# Wait for instance to be running
echo "Waiting for instance to be running..."
aws ec2 wait instance-running \
  --instance-ids "$INSTANCE_ID" \
  --region "$AWS_REGION"

# Get public IP address
PUBLIC_IP=$(aws ec2 describe-instances \
  --instance-ids "$INSTANCE_ID" \
  --region "$AWS_REGION" \
  --query "Reservations[0].Instances[0].PublicIpAddress" \
  --output text)

echo "Instance is now running!"
echo "Public IP: $PUBLIC_IP"
echo "Status page will be available at: http://$PUBLIC_IP"
echo "Gradio app will be available at: http://$PUBLIC_IP:8081"
echo "Note: It may take 10-15 minutes for the application to initialize completely."
echo "To SSH into the instance: ssh -i $KEY_NAME.pem ubuntu@$PUBLIC_IP"
echo "To terminate the instance when done, run: aws ec2 terminate-instances --instance-ids $INSTANCE_ID --region $AWS_REGION"

# Clean up temporary directory
rm -rf "$TEMP_DIR"
