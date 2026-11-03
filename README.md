# CYPHR // Ultra-Lightweight E2EE Real-Time Messaging

A privacy-focused, mobile-first Instant Messaging (IM) web application built specifically for ultra-low-resource environments (e.g., **Oracle Linux VPS with 1 GB RAM and dual-core CPU**).

---

## 🚀 Key Highlights & Architectural Decisions

1. **Ultra-Low Memory Footprint (< 20 MB RAM):**
   - Written in **Go**, compiled into a single static binary with static assets embedded via `go:embed`.
   - Tuned runtime with `GOMEMLIMIT=128MiB` and aggressive garbage collection (`GOGC=50`).
   - No external database or disk storage required.
2. **End-to-End Encryption (E2EE):**
   - Utilizes the browser's native **Web Crypto API** with **AES-256-GCM** and **PBKDF2** key derivation (100,000 rounds).
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
│   ├── nginx.conf             # Production Nginx reverse proxy + TLS + WebSocket upgrade
│   └── im-server.service      # Systemd service unit with memory limit cgroups
├── DEPLOYMENT.md              # Complete Oracle Linux deployment & internet access guide
├── go.mod
└── README.md
```

---

## 🛠️ Quickstart (Local Development)

### Prerequisites
- Go 1.22+ (tested up to Go 1.26)

### Run Server
```bash
go run ./cmd/server
```

Open your browser to `http://localhost:8080`.

### Run Tests
```bash
go test -v ./...
```

---

## 🌐 How to Deploy Online and Access via Internet

For the complete, copy-paste deployment guide with exact commands, see **[DEPLOYMENT.md](DEPLOYMENT.md)**.

### Summary of Deployment Steps on Oracle Linux:
1. **Find Public IP:** `curl -4 ifconfig.me`
2. **Open Firewall Ports:** Run `sudo firewall-cmd --permanent --add-service=http --add-service=https --add-port=8080/tcp && sudo firewall-cmd --reload` and ensure port 80/443 ingress is allowed in your Oracle Cloud VCN Security List.
3. **Set Up 2GB Swap:** Prevents OOM memory issues on the 1GB VPS.
4. **Compile & Install Daemon:** Build `cyphr-server` into `/opt/im-server/`.
5. **Start Systemd Service:** Enable `deploy/im-server.service` with automatic restarts and memory limits.
6. **Configure Nginx & Free SSL:** Set up `deploy/nginx.conf` and run `certbot --nginx -d chat.yourdomain.com`.

### Finding and Accessing Your Web App:
- **Public Domain (Secure HTTPS):** `https://chat.yourdomain.com`
- **Direct IP (Testing):** `http://<YOUR_SERVER_PUBLIC_IP>:8080`
- Once opened, create a room, click the **🔗** button to copy a private invite link with embedded key fragment (`#room=...&key=...`), and send it to friends to chat in real-time with zero trace!
