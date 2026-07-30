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
