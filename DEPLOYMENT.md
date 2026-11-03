# Production Deployment & Public Internet Access Guide: CYPHR on Oracle Linux (1GB RAM)

This guide takes you through deploying **CYPHR** on an **Oracle Linux** VPS (1GB RAM & dual-core CPU) and accessing it securely over the public internet from any device without needing a domain name.

---

## ⚡ Method 1: The 1-Click Automated Installer (Recommended)

Simply run the included installer script as root:

```bash
sudo bash installation.sh
```

The script will automatically:
1. Detect your public IP.
2. Configure 2GB swap space to guarantee system stability under the 1GB RAM constraint.
3. Install Nginx and build tools.
4. Compile the ultra-lightweight Go server (< 20MB RSS).
5. Set up systemd with memory limit cgroups.
6. Configure Nginx reverse proxy on port 80.
7. Open ports in `firewalld`.
8. Output the ready-to-use URL: **`http://<YOUR_PUBLIC_IP>`**.

---

## 🌐 Method 2: Manual Step-by-Step Installation

### Step 0: Find Your Server's Public IP Address
Run this command in your Oracle Linux terminal:
```bash
curl -4 ifconfig.me
```
*Example: `132.145.20.100`*

---

### Step 1: Open Oracle Cloud & OS Firewall Ports

#### 1.1 In Oracle Cloud (OCI) Console:
1. Go to **Networking** > **Virtual Cloud Networks**.
2. Click your VCN > **Security Lists** > **Default Security List**.
3. Add Ingress Rule:
   - **Source CIDR:** `0.0.0.0/0`
   - **IP Protocol:** `TCP`
   - **Destination Port Range:** `80,8080`

#### 1.2 In Server Terminal (`firewalld`):
```bash
sudo firewall-cmd --permanent --add-service=http
sudo firewall-cmd --permanent --add-port=8080/tcp
sudo firewall-cmd --reload
```

---

### Step 2: Configure 2GB Swap Memory
```bash
sudo fallocate -l 2G /swapfile || sudo dd if=/dev/zero of=/swapfile bs=1M count=2048
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
sudo sysctl vm.swappiness=15
```

---

### Step 3: Install Nginx and Golang
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
