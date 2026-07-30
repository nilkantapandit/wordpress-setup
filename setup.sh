#!/bin/bash

echo "===================================================="
echo "  Interactive LAMP Stack & WordPress Setup Script"
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
echo "2. Installing Apache, MySQL, and PHP..."
echo "----------------------------------------------------"
sudo apt install -y apache2 mysql-server
sudo apt install -y php libapache2-mod-php php-mysql php-curl php-gd php-mbstring php-xml php-xmlrpc php-soap php-intl php-zip

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
    -keyout /etc/ssl/private/apache-selfsigned.key \
    -out /etc/ssl/certs/apache-selfsigned.crt \
    -subj "/C=US/ST=State/L=City/O=Organization/CN=${DOMAIN}"

echo "----------------------------------------------------"
echo "5. Downloading and Extracting WordPress..."
echo "----------------------------------------------------"
cd /tmp
curl -O https://wordpress.org/latest.tar.gz
tar xzvf latest.tar.gz
sudo cp -a /tmp/wordpress/. /var/www/html/${DOMAIN}

echo "----------------------------------------------------"
echo "6. Setting File Permissions..."
echo "----------------------------------------------------"
sudo chown -R www-data:www-data /var/www/html/${DOMAIN}
sudo find /var/www/html/${DOMAIN}/ -type d -exec chmod 750 {} \;
sudo find /var/www/html/${DOMAIN}/ -type f -exec chmod 640 {} \;

echo "----------------------------------------------------"
echo "7. Configuring Apache Virtual Hosts (HTTP & HTTPS)..."
echo "----------------------------------------------------"
sudo cat > /etc/apache2/sites-available/${DOMAIN}.conf <<EOF
<VirtualHost *:80>
    ServerAdmin webmaster@localhost
    ServerName ${DOMAIN}
    ServerAlias www.${DOMAIN}
    DocumentRoot /var/www/html/${DOMAIN}
    
    # Redirect HTTP to HTTPS
    Redirect permanent / https://${DOMAIN}/

    ErrorLog \${APACHE_LOG_DIR}/error.log
    CustomLog \${APACHE_LOG_DIR}/access.log combined
</VirtualHost>

<VirtualHost *:443>
    ServerAdmin webmaster@localhost
    ServerName ${DOMAIN}
    ServerAlias www.${DOMAIN}
    DocumentRoot /var/www/html/${DOMAIN}

    <Directory /var/www/html/${DOMAIN}>
        AllowOverride All
    </Directory>

    SSLEngine on
    SSLCertificateFile /etc/ssl/certs/apache-selfsigned.crt
    SSLCertificateKeyFile /etc/ssl/private/apache-selfsigned.key

    ErrorLog \${APACHE_LOG_DIR}/error.log
    CustomLog \${APACHE_LOG_DIR}/access.log combined
</VirtualHost>
EOF

# Enable the site, rewrite module, and SSL module
sudo a2ensite ${DOMAIN}.conf
sudo a2enmod rewrite
sudo a2enmod ssl
sudo systemctl restart apache2

echo "===================================================="
echo " Setup Complete! "
echo "===================================================="
echo "Your LAMP stack is fully provisioned."
echo "Self-signed SSL is active, and MySQL remote root access is disabled."
