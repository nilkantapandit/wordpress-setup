# ⚡ Secure LAMP Stack & WordPress Provisioner

An interactive Bash script designed to quickly provision a complete, secure LAMP (Linux, Apache, MySQL, PHP) stack and deploy the latest version of WordPress on Ubuntu servers. 

Perfect for spinning up local development environments, staging servers, or base production setups with security best practices baked in from the start.

## ✨ Features

* **Interactive Setup:** Prompts for domain name and database credentials before execution.
* **Full Stack Installation:** Automatically installs Apache2, MySQL Server, and all necessary PHP extensions for WordPress.
* **Hardened MySQL:** Actively removes remote root access and creates a dedicated, restricted database user for WordPress.
* **Automated SSL:** Generates a self-signed SSL certificate and configures Apache to force HTTPS traffic out of the box.
* **WordPress Deployment:** Downloads, extracts, and configures the latest WordPress core files.
* **Secure Permissions:** Sets strict and proper Linux file/folder permissions (`750` for directories, `640` for files) owned by `www-data`.

## 📋 Prerequisites

* A server running **Ubuntu** (Tested on 20.04 LTS and newer).
* A user account with `sudo` privileges.
* An active internet connection to download packages and WordPress core.

## 🚀 Usage

**1. Clone the repository or download the script:**
```bash
git clone https://github.com/nilkantapandit/wordpress-setup.git
cd wordpress-setup

**2. Make the script executable:**
```bash
chmod +x setup.sh

**3. Run the script with sudo privileges:**
```bash
sudo ./setup.sh

**4. Follow the interactive prompts:**
The script will ask you to define
Your Domain Name (e.g., local.dev or yourdomain.com)
A new MySQL Database Name
A new MySQL Database User
A strong MySQL Password
Once completed, navigate to https://yourdomain.com in your web browser to finalize the famous 5-minute WordPress web installation!

🔒 Security Notes
Self-Signed SSL: This script generates a self-signed certificate. Your browser will show a "Not Secure" warning on the first visit. This is completely normal for self-signed local certs. You can safely bypass this in your browser to access the site. (For live production, consider replacing the self-signed cert with Certbot/Let's Encrypt).

MySQL Root Access: The script strictly deletes the root user for any host other than localhost or 127.0.0.1 to prevent unauthorized remote database access.

📄 License
This project is open-source and available under the MIT License.

