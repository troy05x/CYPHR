# Production Deployment Guide: CYPHR on Oracle Linux (1GB RAM)

This guide walks you through deploying the **CYPHR** instant messaging service on an **Oracle Linux** server (version 8 or 9) with **Dual-Core CPU and 1GB RAM**.

---

## 1. System Memory Optimization (Swap Setup)

On a 1GB RAM server, creating a 1GB or 2GB swap file prevents out-of-memory (OOM) kernel panics during package updates or transient traffic spikes.

```bash
# Check existing swap
free -h

# Create a 2GB swap file if none exists
sudo fallocate -l 2G /swapfile || sudo dd if=/dev/zero of=/swapfile bs=1M count=2048
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile

# Make swap persistent across reboots
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab

# Optimize swappiness for low-memory VPS
sudo sysctl vm.swappiness=15
echo 'vm.swappiness=15' | sudo tee -a /etc/sysctl.conf
```

---

## 2. Install Dependencies

Install Nginx, Certbot (for SSL/TLS), and build/runtime utilities:

```bash
# Update package cache
sudo dnf update -y

# Enable EPEL (Extra Packages for Enterprise Linux)
sudo dnf install -y epel-release

# Install Nginx, Certbot, Git, and Golang (if compiling on server)
sudo dnf install -y nginx certbot python3-certbot-nginx git tar
```

---

## 3. Dedicated User and Binary Installation

Create an unprivileged user `imapp` to run the daemon safely:

```bash
# Create system user
sudo useradd -r -s /sbin/nologin -d /opt/im-server imapp

# Create directory
sudo mkdir -p /opt/im-server
sudo chown -R imapp:imapp /opt/im-server
```

### Option A: Build on your machine and copy binary
```bash
# On your local machine (compile for Linux amd64)
CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -ldflags="-s -w" -o cyphr-server ./cmd/server

# Copy binary to server
scp cyphr-server your_user@your-server-ip:/tmp/
sudo mv /tmp/cyphr-server /opt/im-server/
sudo chmod +x /opt/im-server/cyphr-server
sudo chown imapp:imapp /opt/im-server/cyphr-server
```

### Option B: Build directly on the Oracle Linux server
```bash
git clone <your-repo-url> /tmp/im-source
cd /tmp/im-source
go build -ldflags="-s -w" -o /opt/im-server/cyphr-server ./cmd/server
sudo chmod +x /opt/im-server/cyphr-server
sudo chown imapp:imapp /opt/im-server/cyphr-server
rm -rf /tmp/im-source
```

---

## 4. Setup Systemd Service

Copy the provided systemd service unit into `/etc/systemd/system/`:

```bash
sudo cp deploy/im-server.service /etc/systemd/system/im-server.service
sudo systemctl daemon-reload
sudo systemctl enable im-server
sudo systemctl start im-server

# Check service status and memory usage
sudo systemctl status im-server
```

---

## 5. Configure Firewall (`firewalld`)

Oracle Linux enables `firewalld` by default. Open HTTP (80) and HTTPS (443):

```bash
sudo firewall-cmd --permanent --add-service=http
sudo firewall-cmd --permanent --add-service=https
sudo firewall-cmd --reload
```

*(Note: If using Oracle Cloud Infrastructure (OCI), also ensure ingress rules for TCP port 80 and 443 are allowed in your OCI Virtual Cloud Network (VCN) Security Lists).*

---

## 6. Configure Nginx and SSL/TLS

### 6.1 Deploy Nginx Config
```bash
# Copy config
sudo cp deploy/nginx.conf /etc/nginx/conf.d/cyphr.conf

# Edit domain name
sudo sed -i 's/your-domain.com/chat.yourdomain.com/g' /etc/nginx/conf.d/cyphr.conf
```

### 6.2 Obtain Free SSL Certificate via Let's Encrypt Certbot
```bash
# Obtain certificate and let Certbot configure Nginx
sudo certbot --nginx -d chat.yourdomain.com
```

### 6.3 Test and Start Nginx
```bash
sudo nginx -t
sudo systemctl enable nginx
sudo systemctl restart nginx
```

---

## 7. Monitoring & Healthchecks

The server exposes a zero-leak memory healthcheck at `/healthz`:

```bash
curl http://127.0.0.1:8080/healthz
```

Output:
```json
{"status":"ok","rooms":0,"clients":0,"alloc_mb":2.42,"sys_mb":18.25}
```

- **Memory Footprint:** Typically **under 20 MB RSS**, leaving ~980 MB of RAM available for the OS and Nginx.
- **Process Memory Cap:** Restricted to 192MB maximum via systemd cgroups.
- **WebSocket Upgrade:** Tested and configured for persistent real-time streaming with zero disk writes.
