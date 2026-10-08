#!/bin/bash

echo "===================================================="
echo "  Interactive LAMP Stack & WordPress Setup Script"
echo "  (SSL + MySQL Lockdown)"
echo "===================================================="

# ----------------------------------------------------
# Prompt for configuration details
# ----------------------------------------------------

read -p "Enter your Domain Name (e.g., yourdomain.com): " DOMAIN
read -p "Enter the new MySQL Database Name for WordPress: " DB_NAME
read -p "Enter the new MySQL Database User: " DB_USER
read -s -p "Enter the MySQL Database Password: " DB_PASS
echo ""

echo ""
read -p "Is DNS already configured for ${DOMAIN} and pointing to this server? (y/n): " DNS_CONFIGURED
echo ""

# Normalize answer
DNS_CONFIGURED=$(echo "$DNS_CONFIGURED" | tr '[:upper:]' '[:lower:]')

# ----------------------------------------------------
# Basic domain validation
# ----------------------------------------------------

if [[ ! "$DOMAIN" =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
    echo "ERROR: Invalid domain name: $DOMAIN"
    exit 1
fi

# ----------------------------------------------------
# 1. Update System Packages
# ----------------------------------------------------

echo "----------------------------------------------------"
echo "1. Updating System Packages..."
echo "----------------------------------------------------"

sudo apt update && sudo apt upgrade -y

if [ $? -ne 0 ]; then
    echo "ERROR: Failed to update system packages."
    exit 1
fi

# ----------------------------------------------------
# 2. Install Apache, MySQL, PHP and required packages
# ----------------------------------------------------

echo "----------------------------------------------------"
echo "2. Installing Apache, MySQL, PHP and Required Tools..."
echo "----------------------------------------------------"

sudo apt install -y \
    apache2 \
    mysql-server \
    dnsutils \
    curl \
    openssl \
    certbot \
    python3-certbot-apache

sudo apt install -y \
    php \
    libapache2-mod-php \
    php-mysql \
    php-curl \
    php-gd \
    php-mbstring \
    php-xml \
    php-xmlrpc \
    php-soap \
    php-intl \
    php-zip

if [ $? -ne 0 ]; then
    echo "ERROR: Failed to install required packages."
    exit 1
fi

# ----------------------------------------------------
# 3. Secure MySQL & Create WordPress Database
# ----------------------------------------------------

echo "----------------------------------------------------"
echo "3. Securing MySQL & Creating WordPress Database..."
echo "----------------------------------------------------"

# Explicitly deny remote root access
sudo mysql -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');"
sudo mysql -e "FLUSH PRIVILEGES;"

# Create WordPress database
sudo mysql -e "CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\` DEFAULT CHARACTER SET utf8 COLLATE utf8_unicode_ci;"

# Create WordPress database user
sudo mysql -e "CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';"

# Ensure password is correct if user already exists
sudo mysql -e "ALTER USER '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';"

# Grant privileges
sudo mysql -e "GRANT ALL ON \`${DB_NAME}\`.* TO '${DB_USER}'@'localhost';"
sudo mysql -e "FLUSH PRIVILEGES;"

echo "MySQL database and user configured successfully."

# ----------------------------------------------------
# 4. Download and Extract WordPress
# ----------------------------------------------------

echo "----------------------------------------------------"
echo "4. Downloading and Extracting WordPress..."
echo "----------------------------------------------------"

cd /tmp || exit 1

rm -rf /tmp/wordpress
rm -f /tmp/latest.tar.gz

curl -fsSLO https://wordpress.org/latest.tar.gz

if [ $? -ne 0 ]; then
    echo "ERROR: Failed to download WordPress."
    exit 1
fi

tar xzf latest.tar.gz

if [ ! -d "/tmp/wordpress" ]; then
    echo "ERROR: WordPress extraction failed."
    exit 1
fi

sudo mkdir -p "/var/www/html/${DOMAIN}"

sudo cp -a /tmp/wordpress/. "/var/www/html/${DOMAIN}"

# ----------------------------------------------------
# 5. Set File Permissions
# ----------------------------------------------------

echo "----------------------------------------------------"
echo "5. Setting File Permissions..."
echo "----------------------------------------------------"

sudo chown -R www-data:www-data "/var/www/html/${DOMAIN}"

sudo find "/var/www/html/${DOMAIN}/" \
    -type d \
    -exec chmod 750 {} \;

sudo find "/var/www/html/${DOMAIN}/" \
    -type f \
    -exec chmod 640 {} \;

# ----------------------------------------------------
# 6. Configure Apache Virtual Hosts
# ----------------------------------------------------

echo "----------------------------------------------------"
echo "6. Configuring Apache Virtual Hosts..."
echo "----------------------------------------------------"

sudo tee "/etc/apache2/sites-available/${DOMAIN}.conf" > /dev/null <<EOF
<VirtualHost *:80>

    ServerAdmin webmaster@localhost
    ServerName ${DOMAIN}
    ServerAlias www.${DOMAIN}

    DocumentRoot /var/www/html/${DOMAIN}

    <Directory /var/www/html/${DOMAIN}>
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/${DOMAIN}-error.log
    CustomLog \${APACHE_LOG_DIR}/${DOMAIN}-access.log combined

</VirtualHost>
EOF

# ----------------------------------------------------
# 7. Enable Apache Modules and Site
# ----------------------------------------------------

echo "----------------------------------------------------"
echo "7. Enabling Apache Site and Required Modules..."
echo "----------------------------------------------------"

sudo a2dissite 000-default.conf
sudo a2enmod rewrite

sudo a2ensite "${DOMAIN}.conf"

sudo apache2ctl configtest

if [ $? -ne 0 ]; then
    echo "ERROR: Apache configuration test failed."
    exit 1
fi

sudo systemctl restart apache2

# ----------------------------------------------------
# 8. SSL Configuration
# ----------------------------------------------------

echo "----------------------------------------------------"
echo "8. Configuring SSL..."
echo "----------------------------------------------------"

if [[ "$DNS_CONFIGURED" == "y" || "$DNS_CONFIGURED" == "yes" ]]; then

    echo ""
    echo "DNS verification selected."
    echo "Checking DNS configuration..."
    echo ""

    # Get this server's public IPv4
    SERVER_IP=$(curl -4 -s --max-time 10 https://api.ipify.org)

    if [ -z "$SERVER_IP" ]; then
        echo "ERROR: Could not determine this server's public IPv4 address."
        exit 1
    fi

    echo "This server's public IP: $SERVER_IP"

    # Resolve domain A record
    DNS_IP=$(dig +short A "$DOMAIN" | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | tail -n 1)

    echo "DNS A record for ${DOMAIN}: ${DNS_IP:-NOT FOUND}"

    if [ -z "$DNS_IP" ]; then
        echo ""
        echo "ERROR: No A record found for ${DOMAIN}."
        echo "Please configure DNS and run the script again."
        exit 1
    fi

    if [ "$DNS_IP" != "$SERVER_IP" ]; then
        echo ""
        echo "ERROR: DNS does not point to this server."
        echo ""
        echo "Expected IP : $SERVER_IP"
        echo "DNS IP      : $DNS_IP"
        echo ""
        echo "Please correct the DNS A record and run the script again."
        exit 1
    fi

    echo ""
    echo "DNS verification successful."
    echo "${DOMAIN} correctly points to ${SERVER_IP}."
    echo ""

    # ------------------------------------------------
    # Configure HTTPS VirtualHost temporarily
    # Certbot will modify this configuration.
    # ------------------------------------------------

    sudo tee "/etc/apache2/sites-available/${DOMAIN}.conf" > /dev/null <<EOF
<VirtualHost *:80>

    ServerAdmin webmaster@localhost
    ServerName ${DOMAIN}
    ServerAlias www.${DOMAIN}

    DocumentRoot /var/www/html/${DOMAIN}

    <Directory /var/www/html/${DOMAIN}>
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/${DOMAIN}-error.log
    CustomLog \${APACHE_LOG_DIR}/${DOMAIN}-access.log combined

</VirtualHost>
EOF

    sudo apache2ctl configtest

    if [ $? -ne 0 ]; then
        echo "ERROR: Apache configuration test failed before Certbot."
        exit 1
    fi

    sudo systemctl reload apache2

    echo "----------------------------------------------------"
    echo "Requesting Let's Encrypt SSL Certificate..."
    echo "----------------------------------------------------"

    sudo certbot --apache \
        -d "${DOMAIN}" \
        -d "www.${DOMAIN}" \
        --non-interactive \
        --agree-tos \
        --register-unsafely-without-email \
        --redirect

    if [ $? -ne 0 ]; then
        echo ""
        echo "ERROR: Let's Encrypt certificate generation failed."
        echo ""
        echo "The WordPress installation is still present."
        echo "You can fix DNS/validation and run Certbot manually later."
        echo ""
        echo "Manual command:"
        echo "sudo certbot --apache -d ${DOMAIN} -d www.${DOMAIN}"
        exit 1
    fi

    echo ""
    echo "Let's Encrypt SSL certificate installed successfully."
    echo "HTTP traffic will redirect to HTTPS."

else

    if [[ "$DNS_CONFIGURED" != "n" && "$DNS_CONFIGURED" != "no" ]]; then
        echo "ERROR: Please answer DNS configuration question with y/yes or n/no."
        exit 1
    fi

    echo ""
    echo "DNS is not configured yet."
    echo "Creating self-signed SSL certificate..."
    echo ""

    # Generate self-signed certificate
    sudo openssl req \
        -x509 \
        -nodes \
        -days 365 \
        -newkey rsa:2048 \
        -keyout /etc/ssl/private/apache-selfsigned.key \
        -out /etc/ssl/certs/apache-selfsigned.crt \
        -subj "/C=US/ST=State/L=City/O=Organization/CN=${DOMAIN}"

    # ------------------------------------------------
    # Create HTTPS VirtualHost
    # ------------------------------------------------

    sudo tee "/etc/apache2/sites-available/${DOMAIN}.conf" > /dev/null <<EOF
<VirtualHost *:80>

    ServerAdmin webmaster@localhost
    ServerName ${DOMAIN}
    ServerAlias www.${DOMAIN}

    DocumentRoot /var/www/html/${DOMAIN}

    # Redirect HTTP to HTTPS
    Redirect permanent / https://${DOMAIN}/

    ErrorLog \${APACHE_LOG_DIR}/${DOMAIN}-error.log
    CustomLog \${APACHE_LOG_DIR}/${DOMAIN}-access.log combined

</VirtualHost>

<VirtualHost *:443>

    ServerAdmin webmaster@localhost
    ServerName ${DOMAIN}
    ServerAlias www.${DOMAIN}

    DocumentRoot /var/www/html/${DOMAIN}

    <Directory /var/www/html/${DOMAIN}>
        AllowOverride All
        Require all granted
    </Directory>

    SSLEngine on
    SSLCertificateFile /etc/ssl/certs/apache-selfsigned.crt
    SSLCertificateKeyFile /etc/ssl/private/apache-selfsigned.key

    ErrorLog \${APACHE_LOG_DIR}/${DOMAIN}-ssl-error.log
    CustomLog \${APACHE_LOG_DIR}/${DOMAIN}-ssl-access.log combined

</VirtualHost>
EOF

    # Enable SSL
    sudo a2enmod ssl

    # Test Apache configuration
    sudo apache2ctl configtest

    if [ $? -ne 0 ]; then
        echo "ERROR: Apache configuration test failed."
        exit 1
    fi

    sudo systemctl restart apache2

    echo ""
    echo "Self-signed SSL certificate created successfully."
    echo ""
    echo "IMPORTANT:"
    echo "The browser will show a certificate warning because this"
    echo "certificate is self-signed."
    echo ""
    echo "Once DNS is configured, you can obtain a trusted"
    echo "Let's Encrypt certificate using:"
    echo ""
    echo "sudo certbot --apache -d ${DOMAIN} -d www.${DOMAIN}"
    echo ""
fi

# ----------------------------------------------------
# Final Status
# ----------------------------------------------------

echo "===================================================="
echo " Setup Complete!"
echo "===================================================="

echo ""
echo "Domain       : ${DOMAIN}"
echo "WordPress    : /var/www/html/${DOMAIN}"
echo "Database     : ${DB_NAME}"
echo "DB User      : ${DB_USER}"

if [[ "$DNS_CONFIGURED" == "y" || "$DNS_CONFIGURED" == "yes" ]]; then
    echo "SSL          : Let's Encrypt"
else
    echo "SSL          : Self-Signed"
fi

echo ""
echo "Your LAMP stack is fully provisioned."
echo "MySQL remote root access is disabled."
echo "===================================================="
