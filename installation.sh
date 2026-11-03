#!/usr/bin/env bash
# ==============================================================================
# CYPHR - 1-Click Automated Installer for Oracle Linux (1GB RAM)
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
echo "⚡ CYPHR: Starting Automated Installation for Oracle Linux"
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

# Detect Package Manager (dnf or yum)
if command -v dnf &> /dev/null; then
  PKG_MGR="dnf"
elif command -v yum &> /dev/null; then
  PKG_MGR="yum"
else
  log_err "Neither dnf nor yum package manager found! This script requires Oracle Linux/RHEL."
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
# 5. Review & Install Core System Prerequisites
# ------------------------------------------------------------------------------
log_info "Checking and installing system packages (EPEL, Nginx, Git, Tar, Curl)..."
$PKG_MGR install -y epel-release || true
$PKG_MGR install -y nginx git tar gzip curl coreutils util-linux procps-ng

# ------------------------------------------------------------------------------
# 6. Review & Install Go Compiler
# ------------------------------------------------------------------------------
NEED_GO_INSTALL=0
if command -v go &> /dev/null; then
  GO_VER=$(go version | awk '{print $3}' | sed 's/go//')
  log_info "Found existing Go version: ${GO_VER}"
else
  NEED_GO_INSTALL=1
fi

if [ "$NEED_GO_INSTALL" -eq 1 ]; then
  log_info "Go compiler not found. Installing Golang..."
  if ! $PKG_MGR install -y golang; then
    log_info "Package manager golang unavailable, downloading official Go binary tarball..."
    GO_ARCH="amd64"
    if [ "$ARCH" = "aarch64" ]; then
      GO_ARCH="arm64"
    fi
    curl -fsSL "https://go.dev/dl/go1.22.6.linux-${GO_ARCH}.tar.gz" -o /tmp/go.tar.gz
    rm -rf /usr/local/go && tar -C /usr/local -xzf /tmp/go.tar.gz
    rm -f /tmp/go.tar.gz
    ln -sf /usr/local/go/bin/go /usr/bin/go
  fi
fi

# Verify Go runs
if ! command -v go &> /dev/null; then
  log_err "Failed to install Go compiler! Please install Go manually."
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
# Remove any conflicting default configs in conf.d
rm -f /etc/nginx/conf.d/default.conf

cp "${SCRIPT_DIR}/deploy/nginx.conf" /etc/nginx/conf.d/cyphr.conf

nginx -t
systemctl enable nginx
systemctl restart nginx

# ------------------------------------------------------------------------------
# 12. Configure Firewall (firewalld)
# ------------------------------------------------------------------------------
if command -v firewall-cmd &> /dev/null && systemctl is-active --quiet firewalld; then
  log_info "Configuring firewalld rules for port 80 and 8080..."
  firewall-cmd --permanent --add-service=http || true
  firewall-cmd --permanent --add-service=https || true
  firewall-cmd --permanent --add-port=8080/tcp || true
  firewall-cmd --reload || true
fi

# ------------------------------------------------------------------------------
# 13. Health Check & Verification
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
  log_info "Healthcheck PASSED! Service is responsive."
else
  log_warn "Healthcheck pending. Review status with: journalctl -u im-server -n 20"
fi

echo ""
echo "=================================================================="
echo "🎉 CYPHR INSTALLATION COMPLETED SUCCESSFULLY!"
echo "=================================================================="
echo ""
echo "Access the private messaging app from your browser at:"
echo ""
echo "   👉  http://${PUBLIC_IP}"
echo ""
echo "Alternative direct port (if port 80 is blocked by ISP):"
echo "   👉  http://${PUBLIC_IP}:8080"
echo ""
echo "📌 ORACLE CLOUD (OCI) INGRESS NOTE:"
echo "If hosted on Oracle Cloud Infrastructure, ensure port 80 & 8080"
echo "are permitted in your VCN Default Security List Ingress Rules."
echo "=================================================================="
echo ""
