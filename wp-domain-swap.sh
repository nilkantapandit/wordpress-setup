#!/usr/bin/env bash
set -Eeuo pipefail

# Reusable WordPress domain swap + optional Let's Encrypt SSL
# Designed for Ubuntu + Apache + WP-CLI.

[[ $EUID -eq 0 ]] || {
    echo "Run using: sudo $0"
    exit 1
}

for cmd in wp python3 apache2ctl systemctl tar; do
    command -v "$cmd" >/dev/null 2>&1 || {
        echo "Missing required command: $cmd"
        exit 1
    }
done

ask_yes_no() {
    local answer
    while true; do
        read -r -p "$1 [y/n]: " answer
        case "${answer,,}" in
            y|yes) return 0 ;;
            n|no) return 1 ;;
            *) echo "Please answer y or n." ;;
        esac
    done
}

valid_domain() {
    [[ "$1" =~ ^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$ ]] &&
    [[ "$1" == *.* ]] &&
    [[ "$1" != *..* ]]
}

echo "=========================================="
echo " WordPress Domain Swap + Optional SSL"
echo "=========================================="
echo

read -r -p "Existing domain (e.g. staging.example.com): " OLD_DOMAIN
read -r -p "Replacement domain (e.g. example.com): " NEW_DOMAIN

OLD_DOMAIN="${OLD_DOMAIN#https://}"
OLD_DOMAIN="${OLD_DOMAIN#http://}"
NEW_DOMAIN="${NEW_DOMAIN#https://}"
NEW_DOMAIN="${NEW_DOMAIN#http://}"
OLD_DOMAIN="${OLD_DOMAIN%/}"
NEW_DOMAIN="${NEW_DOMAIN%/}"

OLD_DOMAIN="${OLD_DOMAIN,,}"
NEW_DOMAIN="${NEW_DOMAIN,,}"

valid_domain "$OLD_DOMAIN" || {
    echo "Invalid existing domain."
    exit 1
}
valid_domain "$NEW_DOMAIN" || {
    echo "Invalid replacement domain."
    exit 1
}
[[ "$OLD_DOMAIN" != "$NEW_DOMAIN" ]] || {
    echo "Domains are identical."
    exit 1
}

echo
echo "Searching for WordPress installations..."
mapfile -t WP_CONFIGS < <(
    find /var/www /srv/www /home -type f -name wp-config.php \
        -not -path '*/vendor/*' \
        -not -path '*/node_modules/*' \
        2>/dev/null | sort -u
)

if [[ ${#WP_CONFIGS[@]} -eq 0 ]]; then
    read -r -p "Full WordPress directory path: " WP_PATH
elif [[ ${#WP_CONFIGS[@]} -eq 1 ]]; then
    WP_PATH="${WP_CONFIGS[0]%/wp-config.php}"
    echo "Found WordPress: $WP_PATH"
    if ask_yes_no "Use this installation?"; then
        :
    else
        read -r -p "Enter the correct WordPress directory: " WP_PATH
    fi
else
    for i in "${!WP_CONFIGS[@]}"; do
        printf "  %d) %s\n" "$((i+1))" "${WP_CONFIGS[$i]%/wp-config.php}"
    done
    read -r -p "Select installation number: " CHOICE
    [[ "$CHOICE" =~ ^[0-9]+$ ]] &&
        (( CHOICE >= 1 && CHOICE <= ${#WP_CONFIGS[@]} )) || {
        echo "Invalid selection."
        exit 1
    }
    WP_PATH="${WP_CONFIGS[$((CHOICE-1))]%/wp-config.php}"
fi

WP_PATH="$(realpath "$WP_PATH")"
[[ -f "$WP_PATH/wp-config.php" ]] || {
    echo "wp-config.php not found."
    exit 1
}

WP=(wp --path="$WP_PATH" --allow-root)
DB_NAME=$("${WP[@]}" config get DB_NAME)
TABLE_PREFIX=$("${WP[@]}" config get table_prefix --type=variable)

echo
echo "WordPress directory: $WP_PATH"
echo "Database:            $DB_NAME"
echo "Table prefix:        $TABLE_PREFIX"
echo "Domain change:       $OLD_DOMAIN -> $NEW_DOMAIN"
echo

# Check WordPress database connectivity before making changes.
"${WP[@]}" db query "SELECT 1;" >/dev/null || {
    echo "Cannot connect to the configured WordPress database."
    exit 1
}

# DNS tools are needed for the optional verification.
if ! command -v dig >/dev/null 2>&1; then
    echo "The 'dig' command is needed for DNS verification."
    if ask_yes_no "Install dnsutils now?"; then
        apt-get update
        DEBIAN_FRONTEND=noninteractive apt-get install -y dnsutils
    else
        echo "Cannot perform DNS verification without dig."
        exit 1
    fi
fi

check_dns() {
    local domain="$1"
    local ips

    echo
    echo "Checking public DNS for $domain ..."

    echo "A records:"
    dig @1.1.1.1 +time=3 +tries=1 +short A "$domain" |
        grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' || true

    echo "AAAA records:"
    dig @1.1.1.1 +time=3 +tries=1 +short AAAA "$domain" || true

    ips="$(dig @1.1.1.1 +time=3 +tries=1 +short A "$domain" |
        grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' || true)"

    if [[ -z "$ips" ]]; then
        echo "No public IPv4 A record found for $domain."
        return 1
    fi

    echo "Independent resolver check (Google DNS):"
    dig @8.8.8.8 +time=3 +tries=1 +short A "$domain" || true

    return 0
}

echo "DNS readiness check"
if ask_yes_no "Has the replacement domain been pointed to this server?"; then
    if check_dns "$NEW_DOMAIN"; then
        DNS_READY=true
    else
        DNS_READY=false
        echo "DNS does not appear ready for HTTP-01 validation."
    fi
else
    DNS_READY=false
    echo "DNS has not been confirmed."
fi

SSL_ENABLED=false
WWW_DOMAIN=""

if ask_yes_no "Request/configure Let's Encrypt SSL after the domain swap?"; then
    SSL_ENABLED=true

    if ask_yes_no "Also include www.$NEW_DOMAIN in the certificate?"; then
        WWW_DOMAIN="www.$NEW_DOMAIN"
    fi

    if [[ "$DNS_READY" != true ]]; then
        echo
        echo "SSL is selected, but DNS verification did not pass."
        if ask_yes_no "Continue with the domain swap but skip SSL for now?"; then
            SSL_ENABLED=false
        else
            echo "Cancelled before making changes."
            exit 1
        fi
    fi
fi

# Determine the host's public IPv4 address when possible.
SERVER_PUBLIC_IP=""
if command -v curl >/dev/null 2>&1; then
    SERVER_PUBLIC_IP="$(curl -4 -fsS --max-time 5 https://api.ipify.org 2>/dev/null || true)"
fi

if [[ "$DNS_READY" == true && -n "$SERVER_PUBLIC_IP" ]]; then
    DNS_IPS="$(dig @1.1.1.1 +short A "$NEW_DOMAIN" |
        grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' || true)"

    if ! grep -Fxq "$SERVER_PUBLIC_IP" <<< "$DNS_IPS"; then
        echo
        echo "WARNING: DNS A records do not include this server's public IPv4:"
        echo "Server IP: $SERVER_PUBLIC_IP"
        printf 'DNS IPs:\n%s\n' "$DNS_IPS"
        echo "A CDN/reverse proxy (e.g. Cloudflare) may explain this difference."

        if ask_yes_no "Is this domain intentionally routed through a proxy/CDN to this server?"; then
            echo "Proceeding. Let's Encrypt must still be able to validate the domain."
        else
            echo "Domain swap cancelled because DNS does not point directly to this server."
            exit 1
        fi
    fi
fi

if [[ "$SSL_ENABLED" == true && -n "$WWW_DOMAIN" ]]; then
    if ! check_dns "$WWW_DOMAIN"; then
        echo "www DNS is missing."
        if ask_yes_no "Remove www from the certificate request and continue with the root domain only?"; then
            WWW_DOMAIN=""
        else
            echo "Cancelled before making changes."
            exit 1
        fi
    fi
fi

# Locate Apache configuration files that reference the old domain.
mapfile -t APACHE_FILES < <(
    if [[ -d /etc/apache2/sites-available ]]; then
        grep -rlF --include='*.conf' "$OLD_DOMAIN" \
            /etc/apache2/sites-available 2>/dev/null || true
    fi
)

echo
echo "Apache configuration files referencing the old domain:"
if [[ ${#APACHE_FILES[@]} -eq 0 ]]; then
    echo "(none found under sites-available)"
else
    printf '  %s\n' "${APACHE_FILES[@]}"
fi

echo
echo "Review the settings above before continuing."
read -r -p "Type REPLACE to proceed: " CONFIRM
[[ "$CONFIRM" == "REPLACE" ]] || {
    echo "Cancelled."
    exit 0
}

STAMP="$(date '+%Y%m%d-%H%M%S')"
BACKUP_DIR="/var/backups/wp-domain-swap/$STAMP"
mkdir -p "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR"

log() { echo "[$(date '+%F %T')] $*"; }

log "Exporting database backup..."
"${WP[@]}" db export "$BACKUP_DIR/database-before.sql"
[[ -s "$BACKUP_DIR/database-before.sql" ]] || {
    echo "Database backup failed."
    exit 1
}

if [[ -d /etc/apache2/sites-available ]]; then
    tar -czf "$BACKUP_DIR/apache-sites-before.tar.gz" \
        -C /etc/apache2 sites-available sites-enabled
fi

# Save copies of the individual Apache files as an additional safeguard.
for file in "${APACHE_FILES[@]}"; do
    cp -a "$file" "$BACKUP_DIR/$(basename "$file").before"
done

log "Replacing domain references in WordPress tables..."
"${WP[@]}" search-replace \
    "$OLD_DOMAIN" "$NEW_DOMAIN" \
    --all-tables-with-prefix \
    --precise \
    --skip-columns=guid \
    --report-changed-only

log "Updating Apache configuration references..."
OLD_DOMAIN="$OLD_DOMAIN" NEW_DOMAIN="$NEW_DOMAIN" python3 - <<'PY'
import os
from pathlib import Path

old = os.environ["OLD_DOMAIN"]
new = os.environ["NEW_DOMAIN"]

for path in Path("/etc/apache2/sites-available").glob("*.conf"):
    try:
        content = path.read_text()
    except (OSError, UnicodeError):
        continue

    if old not in content:
        continue

    # Replace domain text, including ServerName and ServerAlias references.
    # Filesystem paths are not rewritten.
    updated = content.replace(old, new)
    if updated != content:
        path.write_text(updated)
        print(f"Updated: {path}")
PY

# Configure WordPress's canonical URL.
log "Updating WordPress home and siteurl..."
"${WP[@]}" option update home "https://$NEW_DOMAIN"
"${WP[@]}" option update siteurl "https://$NEW_DOMAIN"

# Request Let's Encrypt SSL only if selected and DNS passed checks.
if [[ "$SSL_ENABLED" == true ]]; then
    echo
    echo "Installing/checking Certbot and Apache plugin..."

    if ! command -v certbot >/dev/null 2>&1; then
        apt-get update
        DEBIAN_FRONTEND=noninteractive apt-get install -y certbot python3-certbot-apache
    elif ! dpkg -s python3-certbot-apache >/dev/null 2>&1; then
        apt-get update
        DEBIAN_FRONTEND=noninteractive apt-get install -y python3-certbot-apache
    fi

    # Apache must be valid before Certbot modifies its configuration.
    if ! apache2ctl configtest; then
        echo "Apache config test failed. Attempting to restore its configuration."
        tar -xzf "$BACKUP_DIR/apache-sites-before.tar.gz" -C /etc/apache2
        echo "Database was changed; backup: $BACKUP_DIR/database-before.sql"
        echo "Database rollback is manual."
        exit 1
    fi

    CERTBOT_ARGS=(--apache --non-interactive --agree-tos --redirect
        --register-unsafely-without-email -d "$NEW_DOMAIN")

    if [[ -n "$WWW_DOMAIN" ]]; then
        CERTBOT_ARGS+=(-d "$WWW_DOMAIN")
    fi

    echo
    echo "Certbot will attempt HTTP-01 validation."
    echo "Port 80 must be reachable, and Apache must serve the requested hostname."
    echo "If validation fails, inspect DNS, security groups/firewall, and virtual hosts."

    if certbot "${CERTBOT_ARGS[@]}"; then
        log "Let's Encrypt certificate issued/configured."
    else
        echo "WARNING: Certbot failed. The domain/database changes have already been made."
        echo "Apache backup: $BACKUP_DIR/apache-sites-before.tar.gz"
        echo "Database backup: $BACKUP_DIR/database-before.sql"
        echo "Fix DNS or HTTP validation, then rerun Certbot manually."
        exit 1
    fi
fi

log "Final Apache configuration test..."
apache2ctl configtest

if ask_yes_no "Reload Apache now?"; then
    systemctl reload apache2
    log "Apache reloaded."
fi

echo
echo "=========================================="
echo "Domain swap completed."
echo "WordPress: $WP_PATH"
echo "Database:  $DB_NAME"
echo "Backup:    $BACKUP_DIR"
echo "=========================================="
echo
echo "Verify the site, redirects, DNS, and HTTPS."
echo "GUID columns were intentionally preserved."
echo "The script does not rename the document-root directory."
