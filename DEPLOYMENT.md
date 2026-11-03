# Production Deployment & Public Internet Access Guide: CYPHR on Ubuntu / Debian / Oracle Linux (1GB RAM)

This guide takes you through deploying **CYPHR** on an **Ubuntu** (20.04, 22.04, 24.04), **Debian**, or **Oracle Linux** VPS (1GB RAM & dual-core CPU) and accessing it securely over the public internet from any device without needing a domain name.

---

## ⚡ Method 1: The 1-Click Automated Installer (Recommended)

Simply run the included installer script as root on your Ubuntu or Oracle Linux server:

```bash
sudo bash installation.sh
```

The script will automatically:
1. Detect your public IP.
2. Detect your package manager (`apt-get`, `dnf`, or `yum`).
3. Configure 2GB swap space to guarantee system stability under the 1GB RAM constraint.
4. Install Nginx, Git, build tools, and modern Go compiler (>= 1.22).
5. Compile the ultra-lightweight Go server (< 20MB RSS).
6. Set up systemd service with memory limit cgroups.
7. Configure Nginx reverse proxy on port 80 (cleaning conflicting default sites).
8. Open ports in `ufw` (Ubuntu) or `firewalld` (Oracle Linux / RHEL).
9. Output the ready-to-use URL: **`http://<YOUR_PUBLIC_IP>`**.

---

## 🌐 Method 2: Manual Step-by-Step Installation for Ubuntu / Debian

### Step 0: Find Your Server's Public IP Address
Run this command in your server terminal:
```bash
curl -4 ifconfig.me
```
*Example: `132.145.20.100`*

---

### Step 1: Open Firewall Ports

#### 1.1 In Cloud Console (OCI, AWS, GCP, DigitalOcean):
Add an Ingress Security Rule:
- **Source CIDR:** `0.0.0.0/0`
- **IP Protocol:** `TCP`
- **Destination Port Range:** `80, 8080`

#### 1.2 In Server Terminal (`ufw` on Ubuntu):
```bash
sudo ufw allow 80/tcp
sudo ufw allow 8080/tcp
sudo ufw reload
```
*(Or if using `firewalld`: `sudo firewall-cmd --permanent --add-service=http && sudo firewall-cmd --permanent --add-port=8080/tcp && sudo firewall-cmd --reload`)*

---

### Step 2: Configure 2GB Swap Memory (Crucial for 1GB VPS)
```bash
sudo fallocate -l 2G /swapfile || sudo dd if=/dev/zero of=/swapfile bs=1M count=2048
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
sudo sysctl vm.swappiness=15
echo 'vm.swappiness=15' | sudo tee -a /etc/sysctl.conf
```

---

### Step 3: Install Nginx, Git, and Golang (Go 1.22+)

#### On Ubuntu / Debian:
```bash
sudo apt-get update
sudo apt-get install -y nginx git curl tar gzip

# Install Go 1.22+ (Ubuntu 20.04 default repo has Go 1.13, so download official binary):
ARCH=$(uname -m)
[ "$ARCH" = "x86_64" ] && GO_ARCH="amd64" || GO_ARCH="arm64"
curl -fsSL "https://go.dev/dl/go1.22.6.linux-${GO_ARCH}.tar.gz" -o /tmp/go.tar.gz
sudo rm -rf /usr/local/go && sudo tar -C /usr/local -xzf /tmp/go.tar.gz
sudo ln -sf /usr/local/go/bin/go /usr/bin/go
go version
```

#### On Oracle Linux / RHEL:
```bash
sudo dnf install -y epel-release
sudo dnf install -y nginx git golang
```

---

### Step 4: Build and Install CYPHR Daemon
```bash
sudo useradd -r -s /sbin/nologin -d /opt/im-server imapp
sudo mkdir -p /opt/im-server

# Build binary
go build -ldflags="-s -w" -o /opt/im-server/cyphr-server ./cmd/server
sudo chmod +x /opt/im-server/cyphr-server
sudo chown -R imapp:imapp /opt/im-server
```

---

### Step 5: Start Systemd Service
```bash
sudo cp deploy/im-server.service /etc/systemd/system/im-server.service
sudo systemctl daemon-reload
sudo systemctl enable im-server
sudo systemctl start im-server
```

---

### Step 6: Configure Nginx for Direct IP Access
```bash
# Disable default site on Ubuntu if present
sudo rm -f /etc/nginx/sites-enabled/default /etc/nginx/conf.d/default.conf

# Install CYPHR reverse proxy config
sudo cp deploy/nginx.conf /etc/nginx/conf.d/cyphr.conf
sudo nginx -t
sudo systemctl enable nginx
sudo systemctl restart nginx
```

---

## 📱 Step 7: How to Access and Use the Application

Open your smartphone or PC browser and enter:
```
http://<YOUR_SERVER_PUBLIC_IP>
```

1. Enter your **Nickname / Callsign**.
2. Enter or click **⚡ Random** for a Room ID.
3. Enter or click **🔑 Key** for an encryption passphrase.
4. Click **ENTER SECURE CHANNEL →**.
5. Click the **🔗** button to copy your private invite link with key fragment (`#room=...&key=...`) to share with friends.
6. Click **GIF** to send animated reactions.
7. Click the left arrow or trash icon to instantly wipe all messages from memory. Zero trace is left on the server.
