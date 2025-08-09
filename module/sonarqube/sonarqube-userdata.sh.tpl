#!/bin/bash

set -e

# === CONFIGURATION ===
SONAR_USER="sonaruser"
SONAR_DIR="/opt/sonarqube"
SONARQUBE_DB_SECRET_PATH="secret/sonarqube/db_credentials"
DB_NAME="sonarqube"
SONAR_ZIP="sonarqube-${SONAR_VERSION}.zip"
SONAR_URL="https://binaries.sonarsource.com/Distribution/sonarqube/${SONAR_ZIP}"

# The VAULT_TOKEN environment variable must be set before running this script
# Example: export VAULT_TOKEN="<your_valid_vault_token>"
export VAULT_ADDR="https://vault.alasoasiko.co.uk" # <-- You must replace this with your Vault server address

# === INSTALL DEPENDENCIES ===
apt update
apt install -y openjdk-17-jdk unzip wget postgresql ufw

# --- Install HashiCorp Vault CLI ---
echo "Installing HashiCorp Vault CLI..."
# Add HashiCorp GPG key
wget -O- https://apt.releases.hashicorp.com/gpg | gpg --dearmor | sudo tee /usr/share/keyrings/hashicorp-archive-keyring.gpg > /dev/null
# Add HashiCorp repository to sources.list
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
# Update and install Vault
apt update
apt install -y vault

# === CREATE SONAR SYSTEM USER WITHOUT LOGIN ===
useradd -r -s /bin/false "$SONAR_USER"

# === DOWNLOAD AND EXTRACT SONARQUBE ===
cd /opt
wget "$SONAR_URL"
unzip "$SONAR_ZIP"
mv sonarqube-"${SONAR_VERSION}" sonarqube
chown -R "$SONAR_USER":"$SONAR_USER" "$SONAR_DIR"

# --- START: New AppRole Login Process ---
# these will be gotten from vault configuration phase
ROLE_ID="${sonarqube_role_id}"
SECRET_ID="${sonarqube_secret_id}"

# Authenticate with Vault using the AppRole and capture the new token.
# The 'jq' tool is used to parse the token from the JSON output.
VAULT_TOKEN=$(vault write -field=token auth/approle/login role_id="$ROLE_ID" secret_id="$SECRET_ID")

# Check if the login was successful
if [ -z "$VAULT_TOKEN" ]; then
    echo "Error: Failed to log in with AppRole. Check your ROLE_ID and SECRET_ID."
    exit 1
fi

export VAULT_TOKEN

# --- END: New AppRole Login Process ---

# === CONFIGURE VAULT TO FETCH DB CREDENTIALS ===
echo "Fetching database credentials from Vault..."
SONARQUBE_DB_USER=$(vault kv get -field=username "$SONARQUBE_DB_SECRET_PATH")
SONARQUBE_DB_PASSWORD=$(vault kv get -field=password "$SONARQUBE_DB_SECRET_PATH")

if [ -z "$SONARQUBE_DB_USER" ] || [ -z "$SONARQUBE_DB_PASSWORD" ]; then
  echo "Error: Failed to retrieve database credentials from Vault. Check your VAULT_TOKEN and path."
  exit 1
fi
echo "Successfully retrieved credentials."

# === CONFIGURE POSTGRESQL ===
# Create user and database
sudo -u postgres psql <<EOF
CREATE USER "$SONARQUBE_DB_USER" WITH ENCRYPTED PASSWORD '$SONARQUBE_DB_PASSWORD';
CREATE DATABASE "$DB_NAME" OWNER "$SONARQUBE_DB_USER";
GRANT ALL PRIVILEGES ON DATABASE "$DB_NAME" TO "$SONARQUBE_DB_USER";
EOF

# === CONFIGURE sonar.properties ===
SONAR_PROP="$SONAR_DIR/conf/sonar.properties"
# Make sure sonar.properties uses the correct database credentials
sed -i "s|#sonar.jdbc.username=.*|sonar.jdbc.username=$SONARQUBE_DB_USER|" "$SONAR_PROP"
sed -i "s|#sonar.jdbc.password=.*|sonar.jdbc.password=$SONARQUBE_DB_PASSWORD|" "$SONAR_PROP"
sed -i "s|#sonar.jdbc.url=.*|sonar.jdbc.url=jdbc:postgresql://localhost/$DB_NAME|" "$SONAR_PROP"

# === INCREASE FILE LIMITS ===
echo "$SONAR_USER soft nofile 65536" >> /etc/security/limits.conf
echo "$SONAR_USER hard nofile 65536" >> /etc/security/limits.conf
echo "vm.max_map_count=262144" >> /etc/sysctl.conf
sysctl -w vm.max_map_count=262144

# === CREATE SYSTEMD SERVICE ===
sudo cat <<EOF > /etc/systemd/system/sonarqube.service
[Unit]
Description=SonarQube service
After=syslog.target network.target postgresql.service

[Service]
Type=forking
ExecStart=/opt/sonarqube/bin/linux-x86-64/sonar.sh start
ExecStop=/opt/sonarqube/bin/linux-x86-64/sonar.sh stop
User=$SONAR_USER
Group=$SONAR_USER
LimitNOFILE=65536
LimitNPROC=4096
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# Allow access to SonarQube port
ufw allow 9000/tcp

# === ENABLE AND START SONARQUBE ===
systemctl daemon-reexec
systemctl daemon-reload
systemctl enable sonarqube
systemctl start sonarqube

# === DONE ===
echo "SonarQube $SONAR_VERSION installed and running"
