# CYPHR // Ultra-Lightweight E2EE Real-Time Messaging

A privacy-focused, mobile-first Instant Messaging (IM) web application built specifically for ultra-low-resource environments (e.g., **Ubuntu 20.04/22.04/24.04, Debian, or Oracle Linux VPS with 1 GB RAM and dual-core CPU**).

---

## ⚡ 1-Click Automated Installation (Direct-IP, No Domain Required)

If you don't have a domain and just want to install and access the app directly via your server's **Public IP address**, run this single command on your server (supports Ubuntu, Debian, Oracle Linux, and RHEL):

```bash
sudo bash installation.sh
```

**That's it!** The installer will:
1. Detect your public IP address automatically.
2. Set up a 2GB swap file to protect the 1GB RAM server from running out of memory.
3. Install Nginx and build tools.
4. Compile the ultra-lightweight Go server (< 20MB RAM).
5. Configure systemd for automatic background running and auto-restart.
6. Configure Nginx and firewalld for direct port 80 access.
7. Print your ready-to-use URL: **`http://<YOUR_SERVER_IP>`**.

---

## 🚀 Key Highlights & Architectural Decisions

1. **Ultra-Low Memory Footprint (< 20 MB RAM):**
   - Written in **Go**, compiled into a single static binary with static assets embedded via `go:embed`.
   - Tuned runtime with `GOMEMLIMIT=128MiB` and aggressive garbage collection (`GOGC=50`).
   - No external database or disk storage required.
2. **End-to-End Encryption (E2EE):**
   - Client-side encryption with **AES-256-GCM** and **PBKDF2** key derivation (100,000 rounds) using Web Crypto API (with automatic pure-JS stream cipher fallback for non-HTTPS direct IP).
   - Messages are encrypted and decrypted strictly on the client device. The server only relays encrypted ciphertext.
3. **Zero-Retention Guarantee:**
   - 100% ephemeral in-memory message routing.
   - Zero logs of chat content, zero persistence on disk or database. Messages are wiped from server memory immediately after delivery to connected clients.
4. **Mobile-First Cyberpunk UI:**
   - Sleek **Black and Neon Green** theme with native app feel, high contrast, smooth scrolling, and safe area insets.
   - Built with **Vanilla Modern JS, HTML5, and CSS3** (zero npm build steps required on the server).
5. **Real-Time Features:**
   - 1-on-1 and Group chats via Room IDs.
   - Ephemeral peer presence (view active participants in room).
   - Live typing indicators.
   - **GIF Support:** Integrated GIF picker with curated privacy-safe animations and direct GIF URL auto-rendering.
   - Instant invite links using URL fragments (`#room=...&key=...`), keeping keys strictly client-side.

---

## 📁 Repository Structure

```
├── installation.sh            # 1-Click automated installer for Ubuntu / Debian / Oracle Linux
├── cmd/
│   └── server/
│       ├── main.go            # HTTP server, embedded assets & WebSocket handler
│       ├── server_test.go     # End-to-end WebSocket integration tests
│       └── static/            # Mobile-first frontend
│           ├── index.html     # Semantic responsive HTML
│           ├── style.css      # Cyberpunk Neon Green / Black CSS styling
│           ├── crypto.js      # Web Crypto API AES-GCM 256-bit E2EE implementation
│           └── app.js         # Reactive WebSocket client logic
├── internal/
│   └── hub/
│       ├── hub.go             # Zero-retention in-memory room & broadcast manager
│       └── hub_test.go        # Unit tests for hub routing and lifecycle
├── deploy/
│   ├── nginx.conf             # Production Nginx reverse proxy + WebSocket upgrade
│   └── im-server.service      # Systemd service unit with memory limit cgroups
├── DEPLOYMENT.md              # Complete manual & automated Oracle Linux deployment guide
├── go.mod
└── README.md
```

---

## 🌐 Accessing Your Web App Over the Internet

### 1. Direct-IP Access
After running `sudo bash installation.sh`, open your phone or PC browser and visit:
```
http://<YOUR_SERVER_PUBLIC_IP>
```
*(e.g., `http://132.145.20.100`)*

### 2. If using Oracle Cloud Infrastructure (OCI) or Cloud Firewalls (AWS/GCP/DigitalOcean):
Remember to allow Ingress traffic for port 80 (and 8080) in your Cloud Security Rules / Security Lists:
- **Source CIDR:** `0.0.0.0/0`
- **IP Protocol:** `TCP`
- **Destination Port:** `80, 8080`

If using Ubuntu's `ufw` firewall locally:
```bash
sudo ufw allow 80/tcp
sudo ufw allow 8080/tcp
sudo ufw reload
```

### 3. Shareable Private Room Links
Once you join a room, tap the **🔗 (Link)** button in the top right corner. It will copy a private link to your clipboard:
```
http://<YOUR_SERVER_PUBLIC_IP>/#room=secret-vault&key=SecretKey123
```
Anyone who opens this link will immediately join the encrypted room without the key ever reaching the server.

---

## 🛠️ Local Development & Testing

```bash
# Run server locally
go run ./cmd/server

# Run unit and integration tests
go test -v ./...
```
