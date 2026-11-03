# Production Deployment & Public Internet Access Guide: CYPHR on Oracle Linux (1GB RAM)

This guide takes you through the **complete step-by-step process** of deploying **CYPHR** on an **Oracle Linux** VPS (with 1GB RAM & dual-core CPU) and accessing it securely over the public internet from any smartphone, tablet, or PC browser.

---

## 🌐 Quick Summary: Accessing Your App on the Internet

After deploying, you can access your web application across the world using either:
1. **With a Domain (Recommended for HTTPS & WebCrypto):**
   `https://chat.yourdomain.com`
2. **Directly via Public IP (For quick testing):**
   `http://<YOUR_PUBLIC_IP>:8080`

---

## 📍 Step 0: Find Your Server's Public IP Address

To access the server over the internet, you need its Public IP.

### Method A: From the Server Terminal
Run this command on your Oracle Linux server:
```bash
curl -4 ifconfig.me
# Or:
curl -s https://api.ipify.org
```
This prints your public IP (e.g. `132.145.20.100`). Keep this number handy!

### Method B: From Oracle Cloud Infrastructure (OCI) Console
If your VPS is hosted on Oracle Cloud:
1. Log in to the [Oracle Cloud Console](https://cloud.oracle.com).
2. Go to **Compute** > **Instances**.
3. Click on your instance name.
4. Under **Primary VNIC**, find **Public IP Address**.

---

## 🛡️ Step 1: Allow Web Traffic in Oracle Cloud & OS Firewall

Oracle Cloud and Oracle Linux have two levels of firewall: OCI Virtual Cloud Network (VCN) and local `firewalld`.

### 1.1 Open Ports in Oracle Cloud VCN (OCI Console)
1. In Oracle Cloud Console, go to **Networking** > **Virtual Cloud Networks**.
2. Click your VCN, then click **Security Lists** (default security list).
3. Click **Add Ingress Rules**:
   - **Source CIDR:** `0.0.0.0/0`
   - **IP Protocol:** `TCP`
   - **Destination Port Range:** `80,443,8080`
   - **Description:** Allow Web and WebSocket traffic
4. Click **Add Ingress Rules**.

### 1.2 Open Ports in Local OS Firewall (`firewalld`)
Run these commands inside your Oracle Linux terminal:
```bash
# Allow HTTP, HTTPS, and port 8080
sudo firewall-cmd --permanent --add-service=http
sudo firewall-cmd --permanent --add-service=https
sudo firewall-cmd --permanent --add-port=8080/tcp
sudo firewall-cmd --reload
```

---

## 💾 Step 2: System Memory Optimization (2GB Swap File)

Because the server only has 1GB of physical RAM, adding swap memory guarantees that background tasks and SSL renewals won't trigger an out-of-memory crash.

```bash
# Check if swap exists
free -h

# Create a 2GB swap file
sudo fallocate -l 2G /swapfile || sudo dd if=/dev/zero of=/swapfile bs=1M count=2048
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile

# Make swap permanent across reboots
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab

# Tune swappiness (15 is optimal for low-memory VPS)
sudo sysctl vm.swappiness=15
echo 'vm.swappiness=15' | sudo tee -a /etc/sysctl.conf
```

---

## 📦 Step 3: Install Required Packages

Install Nginx (for SSL reverse proxy), Certbot, Git, and Golang:

```bash
# Update repositories
sudo dnf update -y

# Install Extra Packages for Enterprise Linux (EPEL)
sudo dnf install -y epel-release

# Install Nginx, Certbot SSL tool, Git, and Golang
sudo dnf install -y nginx certbot python3-certbot-nginx git
```

---

## 🚀 Step 4: Build and Install the CYPHR Daemon

### 4.1 Create a Dedicated Non-Root User
```bash
sudo useradd -r -s /sbin/nologin -d /opt/im-server imapp
sudo mkdir -p /opt/im-server
```

### 4.2 Clone and Compile Binary
```bash
# Clone the repository
git clone https://github.com/your-username/im-server.git /tmp/cyphr-repo
cd /tmp/cyphr-repo

# Compile standalone binary (uses < 20MB RAM, zero runtime bloat)
go build -ldflags="-s -w" -o /opt/im-server/cyphr-server ./cmd/server

# Set permissions
sudo chmod +x /opt/im-server/cyphr-server
sudo chown -R imapp:imapp /opt/im-server

# Clean up build files
rm -rf /tmp/cyphr-repo
```

---

## ⚙️ Step 5: Configure and Start Systemd Daemon

CYPHR includes an enterprise systemd service configuration with automatic restarts and strict memory limit cgroups.

```bash
# Copy systemd service file
sudo cp deploy/im-server.service /etc/systemd/system/im-server.service

# Reload systemd and enable automatic startup on boot
sudo systemctl daemon-reload
sudo systemctl enable im-server
sudo systemctl start im-server

# Check service status
sudo systemctl status im-server
```

You should see `active (running)`.

### Quick Test
Test if the local Go server is responding:
```bash
curl http://127.0.0.1:8080/healthz
```
Output:
```json
{"status":"ok","rooms":0,"clients":0,"alloc_mb":2.42,"sys_mb":18.25}
```
Notice `alloc_mb` is only ~2 MB!

---

## 🔒 Step 6: Configure Nginx Reverse Proxy & Free SSL/TLS

> **Why SSL/TLS is critical:** Modern browsers only enable the `window.crypto.subtle` (Web Crypto API) in secure contexts (`https://` or `localhost`). Setting up free HTTPS via Let's Encrypt ensures full End-to-End Encryption works on all mobile devices.

### 6.1 Point Your Domain to Your Server IP
1. Go to your DNS provider (e.g. Cloudflare, Namecheap, GoDaddy).
2. Add an **A Record**:
   - **Type:** `A`
   - **Name:** `chat` (or `@` for root domain)
   - **Value:** `<YOUR_PUBLIC_IP>` (e.g., `132.145.20.100`)
   - **TTL:** Auto or 5 minutes

### 6.2 Set Up Nginx Configuration
```bash
# Copy Nginx config template
sudo cp deploy/nginx.conf /etc/nginx/conf.d/cyphr.conf

# Replace 'your-domain.com' with your actual domain
sudo sed -i 's/your-domain.com/chat.yourdomain.com/g' /etc/nginx/conf.d/cyphr.conf
```

### 6.3 Generate Free SSL Certificate with Certbot
```bash
sudo certbot --nginx -d chat.yourdomain.com
```
Certbot will automatically verify your domain, create the certificate, and update the Nginx configuration.

### 6.4 Enable and Restart Nginx
```bash
# Verify Nginx syntax
sudo nginx -t

# Enable and start Nginx
sudo systemctl enable nginx
sudo systemctl restart nginx
```

---

## 📱 Step 7: How to Access and Use the Application

Now open any web browser (Safari on iPhone, Chrome on Android, Brave, Edge, Firefox, etc.):

1. Navigate to: **`https://chat.yourdomain.com`**
2. **Set your Callsign / Nickname** (e.g., `Neo`).
3. **Room ID:** Type a name (e.g., `secret-lounge`) or click **⚡ Random**.
4. **Encryption Key:** Enter a shared passphrase or click **🔑 Key** to auto-generate a secure 256-bit key.
5. Click **ENTER SECURE CHANNEL →**.
6. **Invite Friends:**
   - Click the **🔗 (Link)** button at the top right.
   - The private URL fragment `#room=...&key=...` is copied to your clipboard.
   - Send this link to anyone. When they click it, they enter the room and decrypt messages automatically. The key stays inside the browser hash and is **never sent to the server**.
7. **Send GIFs:** Click the **GIF** button on the bottom left to choose an animation or paste any `.gif` image URL.
8. **Wipe Session:** Click the left back arrow or trash can icon anytime to immediately wipe all messages from memory.

---

## 🔍 Useful Maintenance & Monitoring Commands

### View Live Memory & Connection Metrics
```bash
curl http://127.0.0.1:8080/healthz
```

### View Live Server Logs
```bash
sudo journalctl -u im-server -f
```

### Restart Application
```bash
sudo systemctl restart im-server
```

### Check Nginx Status
```bash
sudo systemctl status nginx
```
