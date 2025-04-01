#!/bin/bash
# Script to build and run the HunyuanVideo Docker container on the EC2 instance

set -e

echo "=== Building and running HunyuanVideo Docker container ==="

# Set environment variables
APP_NAME="hunyuan-video"
APP_PORT=8081
HOST_PORT=8081

# Navigate to the application directory
cd "$(dirname "$0")/.."
APP_DIR=$(pwd)

echo "Building Docker image locally on EC2..."
# Build the Docker image
sudo docker build -t $APP_NAME:latest .

# Check if a container with the same name is already running
if [ "$(sudo docker ps -q -f name=$APP_NAME)" ]; then
    echo "Stopping existing container..."
    sudo docker stop $APP_NAME
    sudo docker rm $APP_NAME
fi

# Check if a stopped container with the same name exists
if [ "$(sudo docker ps -aq -f status=exited -f name=$APP_NAME)" ]; then
    echo "Removing stopped container..."
    sudo docker rm $APP_NAME
fi

echo "Running Docker container with GPU support..."
# Run the Docker container with GPU support
sudo docker run -d \
    --name $APP_NAME \
    --restart unless-stopped \
    --gpus all \
    -p $HOST_PORT:$APP_PORT \
    -v $APP_DIR/ckpts:/app/ckpts \
    -e SERVER_NAME=0.0.0.0 \
    -e SERVER_PORT=$APP_PORT \
    $APP_NAME:latest

echo "Container started. The application should be accessible at http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):$HOST_PORT"

# Print container logs
echo "Container logs:"
sudo docker logs $APP_NAME
