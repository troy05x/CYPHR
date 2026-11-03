#!/usr/bin/env bash
# ==============================================================================
# CYPHR - 1-Click Automated Installer for Ubuntu / Debian / Oracle Linux
# Validates & installs all prerequisites, configures swap, builds daemon,
# sets up systemd & Nginx reverse proxy for Direct-IP, and validates health.
# ==============================================================================

set -eo pipefail

log_info() {
  echo -e "\033[1;32m[+] $1\033[0m"
}

log_warn() {
  echo -e "\033[1;33m[!] $1\033[0m"
}

log_err() {
  echo -e "\033[1;31m[-] $1\033[0m"
}

echo ""
echo "=================================================================="
echo "⚡ CYPHR: Starting Automated Installation (Ubuntu/Debian/RHEL/OL)"
echo "=================================================================="
echo ""

# ------------------------------------------------------------------------------
# 1. Root & Privilege Verification
# ------------------------------------------------------------------------------
if [ "$EUID" -ne 0 ]; then
  log_err "Please run this installer with root privileges: sudo bash installation.sh"
  exit 1
fi

# ------------------------------------------------------------------------------
# 2. OS & Architecture Detection
# ------------------------------------------------------------------------------
log_info "Detecting Operating System and Architecture..."
ARCH=$(uname -m)
if [ "$ARCH" != "x86_64" ] && [ "$ARCH" != "aarch64" ]; then
  log_warn "Architecture is ${ARCH}. Tested primarily on x86_64 and aarch64."
fi

if [ -f /etc/os-release ]; then
  . /etc/os-release
  log_info "Detected OS: ${NAME} ${VERSION_ID}"
else
  log_warn "/etc/os-release not found. Proceeding with standard EL package manager."
fi

# Detect Package Manager (apt-get, dnf, or yum)
if command -v apt-get &> /dev/null; then
  PKG_MGR="apt-get"
elif command -v dnf &> /dev/null; then
  PKG_MGR="dnf"
elif command -v yum &> /dev/null; then
  PKG_MGR="yum"
else
  log_err "No supported package manager found (apt-get, dnf, or yum)!"
  exit 1
fi
log_info "Using package manager: ${PKG_MGR}"

# ------------------------------------------------------------------------------
# 3. Public IP Detection
# ------------------------------------------------------------------------------
log_info "Detecting Public IP address..."
PUBLIC_IP=$(curl -s -4 --connect-timeout 5 https://api.ipify.org || \
            curl -s -4 --connect-timeout 5 https://ifconfig.me || \
            hostname -I 2>/dev/null | awk '{print $1}' || echo "YOUR_SERVER_IP")
log_info "Public IP resolved: ${PUBLIC_IP}"

# ------------------------------------------------------------------------------
# 4. Swap Memory Setup (Prevent OOM on 1GB VPS)
# ------------------------------------------------------------------------------
SWAP_ACTIVE=$(swapon --show | wc -l)
if [ "$SWAP_ACTIVE" -le 1 ]; then
  log_info "Configuring 2GB swap file (crucial for 1GB RAM stability)..."
  if ! fallocate -l 2G /swapfile 2>/dev/null; then
    dd if=/dev/zero of=/swapfile bs=1M count=2048 status=progress
  fi
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile

  if ! grep -q "^/swapfile" /etc/fstab; then
    echo '/swapfile none swap sw 0 0' >> /etc/fstab
  fi

  sysctl -w vm.swappiness=15 >/dev/null 2>&1 || true
  if ! grep -q "vm.swappiness" /etc/sysctl.conf 2>/dev/null; then
    echo 'vm.swappiness=15' >> /etc/sysctl.conf
  fi
  log_info "Swap allocated successfully."
else
  log_info "Sufficient swap memory is already configured."
fi

# ------------------------------------------------------------------------------
# 5. Review & Install Core System Prerequisites & Certbot
# ------------------------------------------------------------------------------
log_info "Checking and installing system packages (Nginx, Git, Tar, Curl, Certbot)..."
if [ "$PKG_MGR" = "apt-get" ]; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  apt-get install -y nginx git tar gzip curl coreutils util-linux procps ufw certbot python3-certbot-nginx iptables
else
  $PKG_MGR install -y epel-release || true
  $PKG_MGR install -y nginx git tar gzip curl coreutils util-linux procps-ng certbot python3-certbot-nginx iptables
fi

# ------------------------------------------------------------------------------
# 6. Review & Install Go Compiler (Go 1.22+ required for go:embed and stdlib)
# ------------------------------------------------------------------------------
check_go_version() {
  local binary="${1:-go}"
  if ! command -v "$binary" &> /dev/null; then
    return 1
  fi
  local ver_raw clean_ver major minor
  ver_raw=$("$binary" version 2>/dev/null | awk '{print $3}')
  clean_ver=$(echo "$ver_raw" | sed -E 's/^go//; s/[^0-9.].*//')
  major=$(echo "$clean_ver" | cut -d. -f1)
  minor=$(echo "$clean_ver" | cut -d. -f2)
  if [ -n "$major" ] && [ -n "$minor" ] && { [ "$major" -gt 1 ] || { [ "$major" -eq 1 ] && [ "$minor" -ge 22 ]; }; }; then
    return 0
  fi
  return 1
}

install_official_go() {
  log_info "Downloading and installing official Go 1.22.6 binary..."
  local go_arch="amd64"
  if [ "$ARCH" = "aarch64" ]; then
    go_arch="arm64"
  fi
  curl -fsSL "https://go.dev/dl/go1.22.6.linux-${go_arch}.tar.gz" -o /tmp/go.tar.gz
  rm -rf /usr/local/go
  tar -C /usr/local -xzf /tmp/go.tar.gz
  rm -f /tmp/go.tar.gz

  mkdir -p /usr/local/bin /usr/bin
  ln -sf /usr/local/go/bin/go /usr/local/bin/go
  ln -sf /usr/local/go/bin/gofmt /usr/local/bin/gofmt
  ln -sf /usr/local/go/bin/go /usr/bin/go
  ln -sf /usr/local/go/bin/gofmt /usr/bin/gofmt
  hash -r 2>/dev/null || true
}

# Ensure /usr/local/go/bin and /usr/local/bin are in PATH
export PATH="/usr/local/go/bin:/usr/local/bin:${PATH}"

if check_go_version "go"; then
  log_info "Found compatible Go version: $(go version)"
else
  if command -v go &> /dev/null; then
    log_warn "Installed Go version ($(go version)) is older than required 1.22+."
  else
    log_info "Go compiler not found."
  fi

  # Attempt package manager install first on non-Debian, or directly use official tarball
  INSTALLED_VIA_PKG=0
  if [ "$PKG_MGR" != "apt-get" ]; then
    log_info "Attempting to install Go via ${PKG_MGR}..."
    $PKG_MGR install -y golang || true
    if check_go_version "go"; then
      INSTALLED_VIA_PKG=1
    fi
  fi

  if [ "$INSTALLED_VIA_PKG" -eq 0 ]; then
    install_official_go
  fi
fi

# Verify Go runs and satisfies version requirement
if ! check_go_version "go"; then
  log_err "Go compiler is missing or incompatible (< 1.22)! Please install Go 1.22+ manually."
  exit 1
fi
log_info "Go compiler is ready: $(go version)"

# ------------------------------------------------------------------------------
# 7. Review & Configure SELinux (if enabled)
# ------------------------------------------------------------------------------
if command -v getenforce &> /dev/null; then
  SELINUX_MODE=$(getenforce)
  if [ "$SELINUX_MODE" = "Enforcing" ]; then
    log_info "SELinux is Enforcing: allowing Nginx reverse proxy connections..."
    setsebool -P httpd_can_network_connect 1 || true
  fi
fi

# ------------------------------------------------------------------------------
# 8. Create Dedicated Unprivileged System User
# ------------------------------------------------------------------------------
if ! id "imapp" &>/dev/null; then
  log_info "Creating system service user: imapp"
  useradd -r -s /sbin/nologin -d /opt/im-server imapp
fi
mkdir -p /opt/im-server

# ------------------------------------------------------------------------------
# 9. Compile and Install Application Binary
# ------------------------------------------------------------------------------
log_info "Compiling CYPHR binary with embedded frontend assets..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Ensure dependencies are downloaded
go mod download
go build -ldflags="-s -w" -o /opt/im-server/cyphr-server ./cmd/server
chmod +x /opt/im-server/cyphr-server
chown -R imapp:imapp /opt/im-server
log_info "Binary compiled successfully to /opt/im-server/cyphr-server"

# ------------------------------------------------------------------------------
# 10. Install & Start Systemd Service
# ------------------------------------------------------------------------------
log_info "Installing systemd service unit..."
cp "${SCRIPT_DIR}/deploy/im-server.service" /etc/systemd/system/im-server.service
systemctl daemon-reload
systemctl enable im-server
systemctl restart im-server

# ------------------------------------------------------------------------------
# 11. Configure Nginx Reverse Proxy for Direct IP (Port 80)
# ------------------------------------------------------------------------------
log_info "Configuring Nginx..."
mkdir -p /etc/nginx/conf.d

# Disable default Nginx welcoming page if present to prevent port 80 conflicts
if [ -f /etc/nginx/nginx.conf ]; then
  # Ensure conf.d/*.conf is included in http block
  if ! grep -q "include /etc/nginx/conf.d/\*.conf;" /etc/nginx/nginx.conf; then
    sed -i '/http {/a \    include /etc/nginx/conf.d/*.conf;' /etc/nginx/nginx.conf
  fi
  # Comment out default server block inside /etc/nginx/nginx.conf if present
  sed -i -E 's/listen[[:space:]]+80[[:space:]]+default_server;/listen 80;/g' /etc/nginx/nginx.conf 2>/dev/null || true
  sed -i -E 's/listen[[:space:]]+\[::\]:80[[:space:]]+default_server;/listen [::]:80;/g' /etc/nginx/nginx.conf 2>/dev/null || true
fi
# Remove any conflicting default configs in conf.d or Debian/Ubuntu sites-enabled
rm -f /etc/nginx/conf.d/default.conf
rm -f /etc/nginx/sites-enabled/default

cp "${SCRIPT_DIR}/deploy/nginx.conf" /etc/nginx/conf.d/cyphr.conf

nginx -t
systemctl enable nginx
systemctl restart nginx

# ------------------------------------------------------------------------------
# 12. Configure Firewall (UFW, iptables & firewalld)
# ------------------------------------------------------------------------------
log_info "Configuring firewall rules for HTTP (80), HTTPS (443), and backend (8080)..."

# Ensure HTTPS (Port 443) and HTTP (Port 80) are open in UFW if installed
if command -v ufw &> /dev/null; then
  log_info "Configuring UFW rules (opening 80/tcp, 443/tcp, 8080/tcp)..."
  ufw allow 80/tcp || true
  ufw allow 443/tcp || true
  ufw allow 8080/tcp || true
  if ufw status | grep -q "Status: active"; then
    ufw reload || true
  fi
fi

# Ensure HTTPS (Port 443) and HTTP (Port 80) are opened in iptables
if command -v iptables &> /dev/null; then
  log_info "Configuring iptables rules..."
  if ! iptables -C INPUT -p tcp --dport 80 -j ACCEPT 2>/dev/null; then
    iptables -I INPUT -p tcp --dport 80 -j ACCEPT || true
  fi
  if ! iptables -C INPUT -p tcp --dport 443 -j ACCEPT 2>/dev/null; then
    iptables -I INPUT -p tcp --dport 443 -j ACCEPT || true
  fi
fi

# Configure firewalld if active
if command -v firewall-cmd &> /dev/null && systemctl is-active --quiet firewalld; then
  log_info "Configuring firewalld rules..."
  firewall-cmd --permanent --add-service=http || true
  firewall-cmd --permanent --add-service=https || true
  firewall-cmd --permanent --add-port=8080/tcp || true
  firewall-cmd --reload || true
fi

# ------------------------------------------------------------------------------
# 13. Health Check & Verification of Local Backend
# ------------------------------------------------------------------------------
log_info "Validating server health..."
for i in {1..10}; do
  if curl -s http://127.0.0.1:8080/healthz | grep -q '"status":"ok"'; then
    HEALTHY=1
    break
  fi
  sleep 1
done

if [ "${HEALTHY:-0}" -eq 1 ]; then
  log_info "Backend healthcheck PASSED! Service is responsive."
else
  log_warn "Backend healthcheck pending. Review status with: journalctl -u im-server -n 20"
fi

# ------------------------------------------------------------------------------
# 14. Automated SSL/TLS Certificate Provisioning with Certbot
# ------------------------------------------------------------------------------
DOMAIN="cyphrx.duckdns.org"
EMAIL="admin@cyphrx.duckdns.org"

log_info "Requesting Let's Encrypt SSL/TLS certificate for ${DOMAIN}..."

CERTBOT_SUCCESS=0
if command -v certbot &> /dev/null; then
  if certbot --nginx -d "${DOMAIN}" --non-interactive --agree-tos --redirect -m "${EMAIL}"; then
    CERTBOT_SUCCESS=1
    log_info "Certbot successfully provisioned and configured certificate for ${DOMAIN}."
  else
    log_warn "Certbot automated certificate generation failed. Check that ${DOMAIN} points to this server's IP (${PUBLIC_IP})."
  fi
else
  log_err "Certbot binary not found. Could not provision SSL certificate."
fi

# Automatically test (nginx -t) and reload Nginx upon execution
log_info "Testing and reloading Nginx configuration..."
if nginx -t; then
  systemctl reload nginx
  log_info "Nginx configuration verified and reloaded successfully."
else
  log_err "Nginx configuration test failed!"
fi

# ------------------------------------------------------------------------------
# 15. SSL & Nginx Port 443 Status Checks
# ------------------------------------------------------------------------------
log_info "Verifying SSL certificate and HTTPS listener status..."
SSL_READY=0
if [ -d "/etc/letsencrypt/live/${DOMAIN}" ] || [ -f "/etc/letsencrypt/live/${DOMAIN}/fullchain.pem" ]; then
  log_info "Verified: Let's Encrypt SSL certificate exists for ${DOMAIN}."
  SSL_READY=1
else
  log_warn "Certificate directory /etc/letsencrypt/live/${DOMAIN} not found."
fi

PORT_443_LISTENING=0
if ss -tlpn 2>/dev/null | grep -q ':443 ' || netstat -tlpn 2>/dev/null | grep -q ':443 ' || lsof -i :443 2>/dev/null | grep -q 'LISTEN'; then
  PORT_443_LISTENING=1
  log_info "Verified: Nginx is active and listening on HTTPS Port 443."
else
  log_warn "Port 443 is not currently detected as listening."
fi

echo ""
echo "=================================================================="
if [ "$SSL_READY" -eq 1 ] && [ "$PORT_443_LISTENING" -eq 1 ]; then
  echo "🎉 CYPHR SSL & APPLICATION INSTALLATION COMPLETED SUCCESSFULLY!"
else
  echo "⚡ CYPHR INSTALLATION COMPLETED WITH NOTICES"
fi
echo "=================================================================="
echo ""
echo "Access the private messaging app from your browser at:"
echo ""
echo "   👉  https://${DOMAIN}"
echo ""
echo "Fallback / Direct access:"
echo "   👉  http://${PUBLIC_IP}"
echo "   👉  http://${PUBLIC_IP}:8080"
echo ""
echo "📌 FIREWALL & CLOUD INGRESS NOTE:"
echo "Ensure ports 80, 443, and 8080 are allowed in your Cloud Provider's"
echo "Security List / Security Groups (e.g., Oracle Cloud, AWS, GCP)."
echo "=================================================================="
echo ""
