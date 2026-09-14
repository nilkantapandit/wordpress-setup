#!/bin/bash

echo "===================================================="
echo "  Interactive LEMP Stack & WordPress Setup Script"
echo "  (Includes Self-Signed SSL & MySQL Lockdown)"
echo "===================================================="

# Prompt for database details
read -p "Enter your Domain Name (e.g., yourdomain.com): " DOMAIN
read -p "Enter the new MySQL Database Name for WordPress: " DB_NAME
read -p "Enter the new MySQL Database User: " DB_USER
read -s -p "Enter the MySQL Database Password: " DB_PASS
echo ""

echo "----------------------------------------------------"
echo "1. Updating System Packages..."
echo "----------------------------------------------------"
sudo apt update && sudo apt upgrade -y

echo "----------------------------------------------------"
echo "2. Installing Nginx, MySQL, and PHP-FPM..."
echo "----------------------------------------------------"
sudo apt install -y nginx mysql-server
sudo apt install -y php-fpm php-mysql php-curl php-gd php-mbstring php-xml php-xmlrpc php-soap php-intl php-zip

echo "----------------------------------------------------"
echo "3. Securing MySQL & Creating WordPress Database..."
echo "----------------------------------------------------"
# Explicitly deny remote root access by removing any root user host that isn't localhost
sudo mysql -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');"
sudo mysql -e "FLUSH PRIVILEGES;"

# Create the dedicated WordPress database and user
sudo mysql -e "CREATE DATABASE ${DB_NAME} DEFAULT CHARACTER SET utf8 COLLATE utf8_unicode_ci;"
sudo mysql -e "CREATE USER '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';"
sudo mysql -e "GRANT ALL ON ${DB_NAME}.* TO '${DB_USER}'@'localhost';"
sudo mysql -e "FLUSH PRIVILEGES;"

echo "----------------------------------------------------"
echo "4. Generating Self-Signed SSL Certificate..."
echo "----------------------------------------------------"
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout /etc/ssl/private/nginx-selfsigned.key \
    -out /etc/ssl/certs/nginx-selfsigned.crt \
    -subj "/C=US/ST=State/L=City/O=Organization/CN=${DOMAIN}"

echo "----------------------------------------------------"
echo "5. Downloading and Extracting WordPress..."
echo "----------------------------------------------------"
cd /tmp
curl -O https://wordpress.org/latest.tar.gz
tar xzvf latest.tar.gz
sudo mkdir -p /var/www/${DOMAIN}
sudo cp -a /tmp/wordpress/. /var/www/${DOMAIN}

echo "----------------------------------------------------"
echo "6. Setting File Permissions..."
echo "----------------------------------------------------"
sudo chown -R www-data:www-data /var/www/${DOMAIN}
sudo find /var/www/${DOMAIN}/ -type d -exec chmod 750 {} \;
sudo find /var/www/${DOMAIN}/ -type f -exec chmod 640 {} \;

echo "----------------------------------------------------"
echo "7. Configuring Nginx Server Blocks (HTTP & HTTPS)..."
echo "----------------------------------------------------"
# Dynamically find the PHP-FPM socket version installed
PHP_FPM_SOCK=$(find /run/php/ -name "*.sock" | head -n 1)

sudo cat > /etc/nginx/sites-available/${DOMAIN} <<EOF
server {
    listen 80;
    server_name ${DOMAIN} www.${DOMAIN};
    
    # Redirect HTTP to HTTPS
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl;
    server_name ${DOMAIN} www.${DOMAIN};
    root /var/www/${DOMAIN};
    index index.php index.html index.htm;

    ssl_certificate /etc/ssl/certs/nginx-selfsigned.crt;
    ssl_certificate_key /etc/ssl/private/nginx-selfsigned.key;

    access_log /var/log/nginx/${DOMAIN}.access.log;
    error_log /var/log/nginx/${DOMAIN}.error.log;

    location / {
        # Try to serve file, then directory, then route to index.php
        try_files \$uri \$uri/ /index.php?\$args;
    }

    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:${PHP_FPM_SOCK};
    }

    # Deny access to hidden files like .htaccess
    location ~ /\.ht {
        deny all;
    }
}
EOF

# Enable the site and disable the default Nginx page to prevent conflicts
sudo ln -sf /etc/nginx/sites-available/${DOMAIN} /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default

# Test Nginx configuration and restart
sudo nginx -t
sudo systemctl restart nginx
sudo systemctl restart php$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')-fpm

echo "===================================================="
echo " Setup Complete! "
echo "===================================================="
echo "Your LEMP stack is fully provisioned."
echo "Self-signed SSL is active, and MySQL remote root access is disabled."
