#!/bin/bash
set -e # Exit immediately if a command exits with a non-zero status or an unset variable is used.

# Redirect all output to a log file for debugging
#exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1
echo "Starting Docker Host user data script..."

# --- 1. System Updates ---
echo "Updating system packages..."
apt update -y
apt upgrade -y

# --- 2. Install Docker CE ---
echo "Installing Docker CE..."
# Install packages to allow apt to use a repository over HTTPS
apt install -y apt-transport-https ca-certificates curl gnupg lsb-release

# Add Docker's official GPG key
mkdir -m 0755 -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg

# Set up the stable Docker repository
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Update apt package index and install Docker CE
apt update -y
apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# --- 3. Configure Docker Service ---
echo "Enabling and starting Docker service..."
systemctl start docker
systemctl enable docker

# --- 4. Add ubuntu to docker group ---
echo "Adding ubuntu and jenkins to the docker group..."
usermod -aG docker ubuntu
usermod -aG docker jenkins

# --- 5. Ensure SSM Agent is Installed and Running ---
# Modern Ubuntu AMIs often come with SSM Agent pre-installed (as a snap or deb package).
# This section tries to ensure it's active. If not, it attempts to install it.
echo "Ensuring SSM Agent is installed and running..."

if systemctl is-active --quiet amazon-ssm-agent || systemctl is-active --quiet snap.amazon-ssm-agent.amazon-ssm-agent.service; then
    echo "SSM Agent service is already running."
else
    echo "SSM Agent not found or not running. Attempting to install/start."
    # Try enabling/starting the deb package service (if pre-installed but inactive)
    systemctl enable amazon-ssm-agent || true # '|| true' to prevent script exit if service doesn't exist
    systemctl start amazon-ssm-agent || true

    if systemctl is-active --quiet amazon-ssm-agent; then
        echo "SSM Agent (deb package) is now running."
    elif command -v snap >/dev/null 2>&1; then
        # Fallback to snap installation if debian package isn't working
        echo "Attempting to install SSM Agent via Snap..."
        snap install amazon-ssm-agent --classic
        snap set amazon-ssm-agent cloud=default
        systemctl enable snap.amazon-ssm-agent.amazon-ssm-agent.service || true
        systemctl start snap.amazon-ssm-agent.amazon-ssm-agent.service || true
        if systemctl is-active --quiet snap.amazon-ssm-agent.amazon-ssm-agent.service; then
            echo "SSM Agent (Snap) installed and started."
        else
            echo "WARNING: Failed to install or start SSM Agent via Snap. Attempting debian download."
            # Final fallback to direct deb download if snap fails
            mkdir -p /tmp/ssm_install
            cd /tmp/ssm_install
            wget https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/debian_amd64/amazon-ssm-agent.deb
            dpkg -i amazon-ssm-agent.deb
            systemctl enable amazon-ssm-agent
            systemctl start amazon-ssm-agent
            echo "SSM Agent installed and started via direct debian package."
        fi
    else
        echo "WARNING: Snap is not available. Attempting direct debian package installation for SSM Agent."
        mkdir -p /tmp/ssm_install
        cd /tmp/ssm_install
        wget https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/debian_amd64/amazon-ssm-agent.deb
        dpkg -i amazon-ssm-agent.deb
        systemctl enable amazon-ssm-agent
        systemctl start amazon-ssm-agent
        echo "SSM Agent installed and started via direct debian package."
    fi
fi

echo "Docker Host user data script completed."

# Important Note: For the 'ubuntu' to fully have docker group permissions without a new login,
# a reboot is technically needed. However, since Ansible will connect via SSM and use 'become: true',
# it can typically run Docker commands without issue even before a reboot.