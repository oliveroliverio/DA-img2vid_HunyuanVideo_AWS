# HunyuanVideo AWS Deployment Guide

This guide provides instructions for deploying the HunyuanVideo application on AWS EC2 using best practices.

## Prerequisites

Before deploying, make sure you have:

1. AWS CLI installed and configured with appropriate credentials
2. A VPC and subnet in your AWS account
3. An EC2 key pair for SSH access
4. A security group that allows:
   - SSH access (port 22)
   - HTTP access (port 80)
   - Gradio app access (port 8081)

## Deployment Options

There are two ways to deploy the application:

### Option 1: Using CloudFormation (Recommended)

CloudFormation provides a declarative way to set up AWS resources, making deployment more reliable and repeatable.

```bash
./deploy_with_cloudformation.sh \
  --key-name YOUR_KEY_NAME \
  --vpc-id YOUR_VPC_ID \
  --subnet-id YOUR_SUBNET_ID \
  --region us-west-1 \
  --instance-type g4dn.xlarge
```

### Option 2: Using EC2 Direct Deployment

This option uses a script to directly create and configure an EC2 instance.

```bash
./deploy_to_aws.sh \
  --key-name YOUR_KEY_NAME \
  --security-group YOUR_SECURITY_GROUP_ID \
  --subnet YOUR_SUBNET_ID \
  --region us-west-1 \
  --instance-type g4dn.xlarge
```

## Important Notes

- The deployment builds the Docker container on the EC2 instance itself to avoid local space limitations
- The application requires a GPU-enabled instance (g4dn.xlarge or better recommended)
- Initial deployment may take 10-15 minutes for the application to fully initialize
- The application will be accessible at `http://<EC2-PUBLIC-IP>:8081`
- A status page will be available at `http://<EC2-PUBLIC-IP>`

## Accessing the Application

After deployment completes, you'll receive:
- The public IP address of the EC2 instance
- A URL to access the Gradio web interface
- SSH command to connect to the instance

## Troubleshooting

If you encounter issues:

1. SSH into the instance: `ssh -i YOUR_KEY_NAME.pem ubuntu@<EC2-PUBLIC-IP>`
2. Check Docker container status: `docker ps -a`
3. View container logs: `docker logs hunyuan-video`
4. If needed, rebuild and restart the container: `cd /home/ubuntu/hunyuan-video && ./build_and_run.sh`

## Cleaning Up

To delete the deployment:

- For CloudFormation: `aws cloudformation delete-stack --stack-name hunyuan-video --region us-west-1`
- For EC2 direct deployment: `aws ec2 terminate-instances --instance-ids <INSTANCE-ID> --region us-west-1`
