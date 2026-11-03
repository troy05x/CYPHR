#!/usr/bin/env bash
# ==============================================================================
# CYPHR - 1-Click Automated Installer for Oracle Linux (1GB RAM)
# Supports Direct-IP Access & Zero-Retention Real-time E2EE Instant Messaging
# ==============================================================================

set -e

echo ""
echo "=================================================================="
echo "⚡ CYPHR: Starting Automated Installation for Oracle Linux"
echo "=================================================================="
echo ""

# 1. Check Root
if [ "$EUID" -ne 0 ]; then
  echo "[-] Error: Please run this installer with sudo or as root: sudo bash installation.sh"
  exit 1
fi

# 2. Detect Public IP Address
echo "[+] Detecting Server Public IP address..."
PUBLIC_IP=$(curl -s -4 https://api.ipify.org || curl -s -4 ifconfig.me || hostname -I | awk '{print $1}')
echo "[+] Detected Public IP: ${PUBLIC_IP}"

# 3. Create Swap (Crucial for 1GB VPS stability)
SWAP_EXISTS=$(swapon --show | wc -l)
if [ "$SWAP_EXISTS" -le 1 ]; then
  echo "[+] Setting up 2GB Swap file for 1GB RAM stability..."
  fallocate -l 2G /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=2048
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  if ! grep -q "/swapfile" /etc/fstab; then
    echo '/swapfile none swap sw 0 0' >> /etc/fstab
  fi
  sysctl vm.swappiness=15
  echo 'vm.swappiness=15' >> /etc/sysctl.conf
  echo "[+] Swap configured successfully."
else
  echo "[+] Swap already present, skipping."
fi

# 4. Install Dependencies
echo "[+] Installing Nginx, Git, and utilities via DNF..."
dnf install -y epel-release || true
dnf install -y nginx git tar || yum install -y nginx git tar

# Install Golang if not present
if ! command -v go &> /dev/null; then
  echo "[+] Installing Golang..."
  dnf install -y golang || yum install -y golang
fi

# 5. Create Dedicated Unprivileged User
if ! id "imapp" &>/dev/null; then
  echo "[+] Creating dedicated 'imapp' user..."
  useradd -r -s /sbin/nologin -d /opt/im-server imapp
fi

mkdir -p /opt/im-server

# 6. Build Standalone Binary
echo "[+] Compiling CYPHR binary (optimized for low memory)..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

go build -ldflags="-s -w" -o /opt/im-server/cyphr-server ./cmd/server
chmod +x /opt/im-server/cyphr-server
chown -R imapp:imapp /opt/im-server

# 7. Configure Systemd Service
echo "[+] Installing systemd service (im-server.service)..."
cp "${SCRIPT_DIR}/deploy/im-server.service" /etc/systemd/system/im-server.service
systemctl daemon-reload
systemctl enable im-server
systemctl restart im-server

# 8. Configure Nginx for Direct-IP Port 80
echo "[+] Configuring Nginx reverse proxy for Direct-IP..."
cp "${SCRIPT_DIR}/deploy/nginx.conf" /etc/nginx/conf.d/cyphr.conf

# Check Nginx configuration
nginx -t
systemctl enable nginx
systemctl restart nginx

# 9. Configure OS Firewall (firewalld)
if command -v firewall-cmd &> /dev/null && systemctl is-active --quiet firewalld; then
  echo "[+] Opening ports 80, 443, and 8080 in firewalld..."
  firewall-cmd --permanent --add-service=http || true
  firewall-cmd --permanent --add-service=https || true
  firewall-cmd --permanent --add-port=8080/tcp || true
  firewall-cmd --reload || true
fi

# 10. Verification Health Check
sleep 2
HEALTH=$(curl -s http://127.0.0.1:8080/healthz || echo "failed")
echo "[+] Server Health Status: ${HEALTH}"

echo ""
echo "=================================================================="
echo "🎉 INSTALLATION COMPLETE!"
echo "=================================================================="
echo ""
echo "You can now access your private messaging app from any device at:"
echo ""
echo "   👉 http://${PUBLIC_IP}"
echo ""
echo "(Or direct port: http://${PUBLIC_IP}:8080)"
echo ""
echo "📌 IMPORTANT NOTE FOR ORACLE CLOUD (OCI) USERS:"
echo "If your server is in Oracle Cloud, ensure port 80 and 8080 are opened"
echo "in your OCI Console Security List (Compute > VCN > Security Lists)."
echo "=================================================================="
echo ""
