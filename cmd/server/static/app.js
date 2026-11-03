/**
 * CYPHR Client Application Logic
 * Pure Vanilla Modern JS with WebSockets, Web Crypto E2EE, GIF support, and zero retention.
 */

// Application State
const state = {
  ws: null,
  roomID: "",
  key: "",
  nickname: "",
  clientID: "u_" + Math.random().toString(36).substring(2, 10),
  peers: new Set(),
  typingTimeout: null,
  isTyping: false,
};

// Curated privacy-friendly fallback GIFs
const CURATED_GIFS = [
  { title: "Matrix Code", url: "https://media.giphy.com/media/A06UFEx8jxEwU/giphy.gif" },
  { title: "Hacker Typing", url: "https://media.giphy.com/media/YQitE4YNQNahy/giphy.gif" },
  { title: "Cyberpunk City", url: "https://media.giphy.com/media/26tn3334mvoVClhos/giphy.gif" },
  { title: "Neon Wave", url: "https://media.giphy.com/media/3oEjI6SIIHBdRxXI40/giphy.gif" },
  { title: "Thumbs Up", url: "https://media.giphy.com/media/111ebonMs90YLu/giphy.gif" },
  { title: "Popcorn", url: "https://media.giphy.com/media/GLbiGvv9RiNpK/giphy.gif" },
];

// DOM Elements
const dom = {
  lobbyScreen: document.getElementById("lobbyScreen"),
  chatScreen: document.getElementById("chatScreen"),
  joinForm: document.getElementById("joinForm"),
  nicknameInput: document.getElementById("nicknameInput"),
  roomInput: document.getElementById("roomInput"),
  keyInput: document.getElementById("keyInput"),
  randomRoomBtn: document.getElementById("randomRoomBtn"),
  randomKeyBtn: document.getElementById("randomKeyBtn"),
  toggleKeyVisibility: document.getElementById("toggleKeyVisibility"),
  currentRoomDisplay: document.getElementById("currentRoomDisplay"),
  participantCount: document.getElementById("participantCount"),
  messagesContainer: document.getElementById("messagesContainer"),
  messageInput: document.getElementById("messageInput"),
  chatForm: document.getElementById("chatForm"),
  leaveBtn: document.getElementById("leaveBtn"),
  peersBtn: document.getElementById("peersBtn"),
  peersDrawer: document.getElementById("peersDrawer"),
  closePeersBtn: document.getElementById("closePeersBtn"),
  peerList: document.getElementById("peerList"),
  shareLinkBtn: document.getElementById("shareLinkBtn"),
  clearChatBtn: document.getElementById("clearChatBtn"),
  typingIndicator: document.getElementById("typingIndicator"),
  gifBtn: document.getElementById("gifBtn"),
  gifModal: document.getElementById("gifModal"),
  closeGifBtn: document.getElementById("closeGifBtn"),
  gifGrid: document.getElementById("gifGrid"),
  gifSearchInput: document.getElementById("gifSearchInput"),
  customGifUrlInput: document.getElementById("customGifUrlInput"),
  sendCustomGifBtn: document.getElementById("sendCustomGifBtn"),
  toast: document.getElementById("toast"),
};

// Initialize URL Fragment Parameters (#room=...&key=...)
function parseHashParams() {
  const hash = window.location.hash.substring(1);
  if (!hash) return;
  const params = new URLSearchParams(hash);
  if (params.get("room")) {
    dom.roomInput.value = params.get("room");
  }
  if (params.get("key")) {
    dom.keyInput.value = params.get("key");
  }
  if (params.get("nick")) {
    dom.nicknameInput.value = params.get("nick");
  }
}

// Generate Room / Key Buttons
dom.randomRoomBtn.addEventListener("click", () => {
  dom.roomInput.value = window.e2eeCrypto.generateRandomRoom();
});

dom.randomKeyBtn.addEventListener("click", () => {
  dom.keyInput.value = window.e2eeCrypto.generateRandomKey();
  showToast("Secure AES-256 key generated!");
});

dom.toggleKeyVisibility.addEventListener("click", () => {
  if (dom.keyInput.type === "password") {
    dom.keyInput.type = "text";
    dom.toggleKeyVisibility.textContent = "🔒";
  } else {
    dom.keyInput.type = "password";
    dom.toggleKeyVisibility.textContent = "👁️";
  }
});

// Toast notification
function showToast(msg, duration = 3000) {
  dom.toast.textContent = msg;
  dom.toast.classList.remove("hidden");
  setTimeout(() => {
    dom.toast.classList.add("hidden");
  }, duration);
}

// Join Room handler
dom.joinForm.addEventListener("submit", (e) => {
  e.preventDefault();
  const nick = dom.nicknameInput.value.trim();
  const room = dom.roomInput.value.trim().toLowerCase();
  const key = dom.keyInput.value.trim();

  if (!nick || !room || !key) {
    showToast("Please provide nickname, room ID, and encryption key.");
    return;
  }

  state.nickname = nick;
  state.roomID = room;
  state.key = key;

  connectWebSocket();
});

// WebSocket Connection
function connectWebSocket() {
  const protocol = window.location.protocol === "https:" ? "wss:" : "ws:";
  const wsUrl = `${protocol}//${window.location.host}/ws`;

  state.ws = new WebSocket(wsUrl);

  state.ws.onopen = () => {
    // Send join envelope
    const initPayload = {
      type: "join",
      room_id: state.roomID,
      sender_id: state.clientID,
      nickname: state.nickname,
      timestamp: Date.now(),
    };
    state.ws.send(JSON.stringify(initPayload));

    // Update UI to chat screen
    dom.currentRoomDisplay.textContent = state.roomID;
    dom.lobbyScreen.classList.remove("active");
    dom.chatScreen.classList.add("active");
    dom.messageInput.focus();

    // Auto-update URL hash for easy sharing (without revealing to server)
    window.location.hash = `room=${encodeURIComponent(state.roomID)}&key=${encodeURIComponent(state.key)}`;
  };

  state.ws.onmessage = async (evt) => {
    try {
      const data = JSON.parse(evt.data);
      handleIncomingMessage(data);
    } catch (err) {
      console.error("Message parse error:", err);
    }
  };

  state.ws.onclose = () => {
    appendSystemMessage("Disconnected from server. Zero data was retained.");
    updatePeerDisplay();
  };

  state.ws.onerror = (err) => {
    console.error("WebSocket error:", err);
    showToast("Connection error");
  };
}

// Dispatch incoming server events
async function handleIncomingMessage(msg) {
  switch (msg.type) {
    case "peers":
      state.peers = new Set(msg.members || []);
      updatePeerDisplay();
      break;

    case "join":
      state.peers.add(msg.nickname || msg.sender_id);
      appendSystemMessage(`${escapeHTML(msg.nickname || msg.sender_id)} entered the channel`);
      updatePeerDisplay();
      break;

    case "leave":
      state.peers.delete(msg.nickname || msg.sender_id);
      appendSystemMessage(`${escapeHTML(msg.nickname || msg.sender_id)} left`);
      updatePeerDisplay();
      break;

    case "typing":
      showTypingIndicator(msg.nickname || "Someone");
      break;

    case "msg":
      // Decrypt client-side using Web Crypto API
      const decrypted = await window.e2eeCrypto.decrypt(msg.payload, state.key);
      const isSelf = msg.sender_id === state.clientID;
      if (decrypted !== null) {
        appendMessageBubble({
          sender: msg.nickname || "Unknown",
          isSelf: isSelf,
          text: decrypted,
          isGIF: msg.is_gif,
          timestamp: msg.timestamp || Date.now(),
        });
      } else {
        // Decryption failed (someone used different key or tampered)
        appendSystemMessage(`⚠️ Message from ${escapeHTML(msg.nickname)} could not be decrypted. Check E2EE key!`);
      }
      break;
  }
}

// Update Active Participants
function updatePeerDisplay() {
  const count = state.peers.size;
  dom.participantCount.textContent = `${count} online`;

  dom.peerList.innerHTML = "";
  state.peers.forEach((peer) => {
    const li = document.createElement("li");
    li.className = "peer-item" + (peer === state.nickname ? " self" : "");
    li.innerHTML = `<span class="live-dot"></span> ${escapeHTML(peer)}${peer === state.nickname ? " (you)" : ""}`;
    dom.peerList.appendChild(li);
  });
}

// Peer Drawer toggling
dom.peersBtn.addEventListener("click", () => {
  dom.peersDrawer.classList.toggle("hidden");
});
dom.closePeersBtn.addEventListener("click", () => {
  dom.peersDrawer.classList.add("hidden");
});

// Typing indicator handling
function showTypingIndicator(sender) {
  const textEl = dom.typingIndicator.querySelector(".typing-text");
  textEl.textContent = `${escapeHTML(sender)} is typing`;
  dom.typingIndicator.classList.remove("hidden");

  clearTimeout(state.typingTimeout);
  state.typingTimeout = setTimeout(() => {
    dom.typingIndicator.classList.add("hidden");
  }, 2000);
}

// Send Typing Event throttled
dom.messageInput.addEventListener("input", () => {
  if (!state.isTyping && state.ws && state.ws.readyState === WebSocket.OPEN) {
    state.isTyping = true;
    state.ws.send(JSON.stringify({
      type: "typing",
      room_id: state.roomID,
      sender_id: state.clientID,
      nickname: state.nickname,
    }));
    setTimeout(() => {
      state.isTyping = false;
    }, 1500);
  }
});

// Send Chat Message
dom.chatForm.addEventListener("submit", async (e) => {
  e.preventDefault();
  const text = dom.messageInput.value.trim();
  if (!text || !state.ws) return;

  dom.messageInput.value = "";
  dom.messageInput.style.height = "auto";

  // Check if text is direct GIF url
  const isGIF = isLikelyGifUrl(text);

  await sendEncryptedPayload(text, isGIF);
});

// Auto-expand textarea
dom.messageInput.addEventListener("keydown", (e) => {
  if (e.key === "Enter" && !e.shiftKey) {
    e.preventDefault();
    dom.chatForm.dispatchEvent(new Event("submit"));
  }
});

async function sendEncryptedPayload(text, isGIF = false) {
  if (!state.ws || state.ws.readyState !== WebSocket.OPEN) {
    showToast("Not connected to server");
    return;
  }

  // Encrypt with Web Crypto AES-GCM
  const encryptedPayload = await window.e2eeCrypto.encrypt(text, state.key);

  const envelope = {
    type: "msg",
    room_id: state.roomID,
    sender_id: state.clientID,
    nickname: state.nickname,
    payload: encryptedPayload,
    is_gif: isGIF,
    timestamp: Date.now(),
  };

  state.ws.send(JSON.stringify(envelope));
}

// Append chat bubbles
function appendMessageBubble({ sender, isSelf, text, isGIF, timestamp }) {
  const bubble = document.createElement("div");
  bubble.className = `message-bubble ${isSelf ? "outgoing" : "incoming"}`;

  const timeStr = new Date(timestamp).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" });

  let contentHTML = "";
  if (isGIF || isLikelyGifUrl(text)) {
    contentHTML = `<img src="${escapeHTML(text)}" class="chat-gif-img" alt="Encrypted GIF" loading="lazy" onerror="this.onerror=null;this.replaceWith('[Image failed to load: '+this.src+']')">`;
  } else {
    contentHTML = formatLinksAndText(text);
  }

  bubble.innerHTML = `
    <div class="message-meta">
      <span class="message-sender">${escapeHTML(sender)}</span>
      <span class="message-time">${timeStr}</span>
    </div>
    <div class="message-body">${contentHTML}</div>
  `;

  dom.messagesContainer.appendChild(bubble);
  dom.messagesContainer.scrollTop = dom.messagesContainer.scrollHeight;
}

// System notifications
function appendSystemMessage(msg) {
  const el = document.createElement("div");
  el.className = "system-message";
  el.textContent = msg;
  dom.messagesContainer.appendChild(el);
  dom.messagesContainer.scrollTop = dom.messagesContainer.scrollHeight;
}

// Helper: detect GIF url
function isLikelyGifUrl(url) {
  if (!url || typeof url !== "string") return false;
  return /^(https?:\/\/.*\.(gif|webp|png|jpe?g))(\?.*)?$/i.test(url.trim()) ||
         /^(https?:\/\/(media|i)\.giphy\.com\/.*|https?:\/\/tenor\.com\/.*\.gif)/i.test(url.trim());
}

// Helpers: link formatting and escaping
function escapeHTML(str) {
  if (!str) return "";
  return str.replace(/[&<>'"]/g,
    tag => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', "'": '&#39;', '"': '&quot;' }[tag] || tag)
  );
}

function formatLinksAndText(text) {
  const escaped = escapeHTML(text);
  const urlPattern = /(\b(https?):\/\/[-A-Z0-9+&@#\/%?=~_|!:,.;]*[-A-Z0-9+&@#\/%=~_|])/ig;
  return escaped.replace(urlPattern, '<a href="$1" target="_blank" rel="noopener noreferrer" style="color:var(--neon-green);text-decoration:underline;">$1</a>');
}

// Leave & Wipe Session
dom.leaveBtn.addEventListener("click", () => {
  if (confirm("Leave channel? All messages will be wiped from memory immediately.")) {
    wipeAndReset();
  }
});

function wipeAndReset() {
  if (state.ws) {
    state.ws.close();
    state.ws = null;
  }
  state.peers.clear();
  dom.messagesContainer.innerHTML = "";
  dom.chatScreen.classList.remove("active");
  dom.lobbyScreen.classList.add("active");
  window.location.hash = "";
  showToast("Session wiped. Zero retention.");
}

// Clear local chat screen
dom.clearChatBtn.addEventListener("click", () => {
  dom.messagesContainer.innerHTML = `
    <div class="system-message">Chat screen cleared locally.</div>
  `;
  showToast("Local screen wiped.");
});

// Share Invite Link with URL Fragment
dom.shareLinkBtn.addEventListener("click", () => {
  const shareUrl = `${window.location.origin}${window.location.pathname}#room=${encodeURIComponent(state.roomID)}&key=${encodeURIComponent(state.key)}`;
  if (navigator.clipboard) {
    navigator.clipboard.writeText(shareUrl).then(() => {
      showToast("🔒 Private E2EE invite link copied to clipboard!");
    }).catch(() => {
      prompt("Copy invite link:", shareUrl);
    });
  } else {
    prompt("Copy invite link:", shareUrl);
  }
});

// GIF Picker Modal Logic
dom.gifBtn.addEventListener("click", () => {
  dom.gifModal.classList.toggle("hidden");
  renderGifGrid(CURATED_GIFS);
});
dom.closeGifBtn.addEventListener("click", () => {
  dom.gifModal.classList.add("hidden");
});

function renderGifGrid(gifs) {
  dom.gifGrid.innerHTML = "";
  gifs.forEach(gif => {
    const img = document.createElement("img");
    img.src = gif.url;
    img.className = "gif-thumb";
    img.alt = gif.title;
    img.loading = "lazy";
    img.addEventListener("click", async () => {
      dom.gifModal.classList.add("hidden");
      await sendEncryptedPayload(gif.url, true);
    });
    dom.gifGrid.appendChild(img);
  });
}

// Direct custom GIF URL sender
dom.sendCustomGifBtn.addEventListener("click", async () => {
  const url = dom.customGifUrlInput.value.trim();
  if (!url) return;
  dom.customGifUrlInput.value = "";
  dom.gifModal.classList.add("hidden");
  await sendEncryptedPayload(url, true);
});

// Filter curated GIFs
dom.gifSearchInput.addEventListener("input", (e) => {
  const term = e.target.value.toLowerCase();
  const filtered = CURATED_GIFS.filter(g => g.title.toLowerCase().includes(term));
  renderGifGrid(filtered.length > 0 ? filtered : CURATED_GIFS);
});

// Startup init
window.addEventListener("DOMContentLoaded", () => {
  parseHashParams();
});
