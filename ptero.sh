#!/bin/bash

# === MENU ===
echo "Select an option:"
echo "1) Install Pterodactyl Panel + Wings"
echo "2) Set Panel Domain URL"
echo "3) Exit"
read -p "Enter choice: " choice

if [[ $choice == 2 ]]; then
  read -p "Enter your panel domain (example: panel.example.com): " PANEL_DOMAIN
  sed -i "s/server_name .*/server_name $PANEL_DOMAIN;/" /etc/nginx/sites-available/pterodactyl 2>/dev/null || true
  sed -i "s#--url=.*#--url=https://$PANEL_DOMAIN#" /var/www/pterodactyl/.env 2>/dev/null || true
  echo "Domain updated. Run: systemctl restart nginx"
  exit 0
elif [[ $choice == 3 ]]; then
  echo "Exiting installer."
  exit 0
fi

# Option 1 continues the installer

# ==============================================
#  Pterodactyl Panel + Wings Auto Installer
#  Custom Installer Created for User
# ==============================================

set -e

# --- Functions ---
log() {
  echo -e "\033[1;32m[INFO]\033[0m $1"
}
err() {
  echo -e "\033[1;31m[ERROR]\033[0m $1" >&2
  exit 1
}

# --- Root Check ---
if [[ $EUID -ne 0 ]]; then
  err "Please run this script as root (sudo su)."
fi

# --- OS Check ---
if [[ -f /etc/os-release ]]; then
  . /etc/os-release
else
  err "Cannot detect OS."
fi

if [[ "$ID" != "ubuntu" && "$ID" != "debian" ]]; then
  err "This installer supports only Ubuntu or Debian."
fi

log "Updating system..."
apt update -y && apt upgrade -y

log "Installing dependencies..."
apt install -y zip unzip curl tar wget git lsb-release ca-certificates apt-transport-https software-properties-common jq

# --- MariaDB Installation ---
log "Installing MariaDB..."
apt install -y mariadb-server mariadb-client
systemctl enable mariadb
systemctl start mariadb

# --- MariaDB Secure Setup ---
log "Configuring MariaDB..."
mysql -u root <<EOF
UPDATE mysql.user SET Password=PASSWORD('ptero_pass') WHERE User='root';
DELETE FROM mysql.user WHERE User='';
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;
EOF

# --- Pterodactyl Panel Installation ---
log "Installing Pterodactyl Panel..."
mkdir -p /var/www/pterodactyl
cd /var/www/pterodactyl
curl -Lo panel.tar.gz https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz
tar -xzvf panel.tar.gz
chmod -R 755 storage/* bootstrap/cache/

log "Installing PHP & extensions..."
add-apt-repository ppa:ondrej/php -y
apt update
apt install -y php8.1 php8.1-cli php8.1-common php8.1-gd php8.1-mysql php8.1-pdo php8.1-mbstring php8.1-tokenizer php8.1-bcmath php8.1-xml php8.1-fpm php8.1-curl php8.1-zip

log "Installing Composer..."
curl -sS https://getcomposer.org/installer | php
mv composer.phar /usr/local/bin/composer

log "Configuring Panel..."
cp .env.example .env
composer install --no-dev --optimize-autoloader
php artisan key:generate --force

mysql -u root -p"ptero_pass" <<EOF
CREATE DATABASE panel;
CREATE USER 'ptero'@'127.0.0.1' IDENTIFIED BY 'ptero_pass';
GRANT ALL PRIVILEGES ON panel.* TO 'ptero'@'127.0.0.1';
FLUSH PRIVILEGES;
EOF

php artisan p:environment:setup --url=https://example.com --timezone=UTC --cache=redis --session=redis --queue=redis
php artisan p:environment:database --host=127.0.0.1 --port=3306 --database=panel --username=ptero --password=ptero_pass
php artisan migrate --seed --force

# --- NGINX Setup ---
log "Installing Nginx..."
apt install -y nginx
systemctl enable nginx
systemctl start nginx

cat > /etc/nginx/sites-available/pterodactyl <<'EOF'
server {
    listen 80;
    server_name example.com;
    root /var/www/pterodactyl/public;

    index index.php;

    location / {
        try_files $uri $uri/ /index.php?$query_string;
    }

    location ~ \.php$ {
        fastcgi_pass unix:/run/php/php8.1-fpm.sock;
        include fastcgi_params;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
    }
}
EOF

ln -sf /etc/nginx/sites-available/pterodactyl /etc/nginx/sites-enabled/
systemctl restart nginx

# --- Wings Installation ---
log "Installing Docker..."
apt install -y docker.io
systemctl enable docker
systemctl start docker

log "Installing Wings..."
mkdir -p /etc/pterodactyl
cd /etc/pterodactyl
curl -Lo wings https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_amd64
chmod +x wings

log "Creating Wings config file (placeholder)..."
cat > /etc/pterodactyl/config.yml <<EOF
# Wings configuration will be generated from panel later
EOF

log "Installation complete!"
echo "---------------------------------------"
echo " Pterodactyl Panel Installed"
echo " Panel Directory: /var/www/pterodactyl"
echo " Wings Directory: /etc/pterodactyl"
echo " MariaDB root password: ptero_pass"
echo " Visit your panel at: http://<your-server-ip>"
echo "---------------------------------------"
