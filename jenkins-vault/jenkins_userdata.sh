#!/bin/bash

# Exit on any error
set -e

# Prevent interactive prompts
export DEBIAN_FRONTEND=noninteractive

# # Wait until external network and DNS are reachable
echo "Waiting for apt to be ready..."
until apt update -qq >/dev/null 2>&1; do
  echo "Retrying apt update..."
  sleep 5
done

# Update & install dependencies
sudo apt-get update -yq
sudo apt-get install -yq git maven unzip curl wget gnupg ca-certificates \
                   software-properties-common openjdk-17-jdk

# Install Jenkins
wget -O /etc/apt/keyrings/jenkins-keyring.asc https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key
echo "deb [signed-by=/etc/apt/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/" \
  > /etc/apt/sources.list.d/jenkins.list
sudo apt-get update -yq
sudo apt-get install -yq jenkins

# Start and enable Jenkins
sudo systemctl enable jenkins
sudo systemctl start jenkins

# Install Docker
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" \
  > /etc/apt/sources.list.d/docker.list

sudo apt-get update -yq
sudo apt-get install -yq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Allow Jenkins to use Docker
usermod -aG docker jenkins
sudo systemctl enable docker
sudo systemctl restart docker
sudo systemctl restart jenkins

# Install AWS CLI v2
cd /tmp
curl -s "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip -q awscliv2.zip
./aws/install
sudo rm -rf aws awscliv2.zip

# Install Trivy
wget -q https://github.com/aquasecurity/trivy/releases/latest/download/trivy_0.64.1_Linux-64bit.deb
dpkg -i trivy_0.64.1_Linux-64bit.deb || apt-get install -f -yq
sudo rm trivy_0.64.1_Linux-64bit.deb

# Done
echo "Jenkins setup complete." > /var/log/jenkins-init.log
