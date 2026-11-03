package hub

import (
	"encoding/json"
	"sync"
	"time"

	"golang.org/x/net/websocket"
)

// Message represents a generic WebSocket payload.
// For privacy and zero-retention:
// - Payload is client-side encrypted ciphertext (Web Crypto API AES-GCM).
// - The server NEVER stores messages or logs sensitive contents.
// - Messages are forwarded in-memory to room members and immediately discarded.
type Message struct {
	Type      string   `json:"type"`                // "join", "leave", "msg", "typing", "peers"
	RoomID    string   `json:"room_id"`             // Ephemeral room identifier
	SenderID  string   `json:"sender_id,omitempty"` // Ephemeral participant ID
	Nickname  string   `json:"nickname,omitempty"`  // Display name chosen for this session
	Payload   string   `json:"payload,omitempty"`   // Encrypted ciphertext (for "msg") or status
	IsGIF     bool     `json:"is_gif,omitempty"`    // Flag indicating message contains an encrypted GIF payload
	Timestamp int64    `json:"timestamp,omitempty"` // Unix millisecond timestamp
	Members   []string `json:"members,omitempty"`   // Active members list for "peers" event
}

// Client represents a single connected WebSocket user.
type Client struct {
	ID       string
	Nickname string
	RoomID   string
	ws       *websocket.Conn
	send     chan []byte
	hub      *Hub
}

// Hub maintains the set of active rooms and ephemeral clients.
// It is 100% in-memory with zero disk persistence.
type Hub struct {
	mu         sync.RWMutex
	rooms      map[string]map[string]*Client // roomID -> clientID -> *Client
	register   chan *Client
	unregister chan *Client
	broadcast  chan *Message
	stop       chan struct{}
}

// NewHub creates a new in-memory Hub.
func NewHub() *Hub {
	return &Hub{
		rooms:      make(map[string]map[string]*Client),
		register:   make(chan *Client, 256),
		unregister: make(chan *Client, 256),
		broadcast:  make(chan *Message, 512),
		stop:       make(chan struct{}),
	}
}

// Run starts the event loop handling registration, unregistration, and broadcasting.
func (h *Hub) Run() {
	for {
		select {
		case client := <-h.register:
			h.handleRegister(client)
		case client := <-h.unregister:
			h.handleUnregister(client)
		case msg := <-h.broadcast:
			h.handleBroadcast(msg)
		case <-h.stop:
			return
		}
	}
}

// Close gracefully stops the hub.
func (h *Hub) Close() {
	select {
	case <-h.stop:
	default:
		close(h.stop)
	}
}

func (h *Hub) handleRegister(c *Client) {
	h.mu.Lock()
	defer h.mu.Unlock()

	if _, exists := h.rooms[c.RoomID]; !exists {
		h.rooms[c.RoomID] = make(map[string]*Client)
	}
	h.rooms[c.RoomID][c.ID] = c

	// Build member list
	members := make([]string, 0, len(h.rooms[c.RoomID]))
	for _, member := range h.rooms[c.RoomID] {
		if member.Nickname != "" {
			members = append(members, member.Nickname)
		} else {
			members = append(members, member.ID)
		}
	}

	// Send current peer list directly to new client
	peersMsg := Message{
		Type:      "peers",
		RoomID:    c.RoomID,
		SenderID:  "system",
		Members:   members,
		Timestamp: time.Now().UnixMilli(),
	}
	if b, err := json.Marshal(peersMsg); err == nil {
		select {
		case c.send <- b:
		default:
		}
	}

	// Announce join to other members of the room
	joinMsg := Message{
		Type:      "join",
		RoomID:    c.RoomID,
		SenderID:  c.ID,
		Nickname:  c.Nickname,
		Timestamp: time.Now().UnixMilli(),
		Members:   members,
	}
	h.broadcastToRoomLocked(c.RoomID, joinMsg, c.ID)
}

func (h *Hub) handleUnregister(c *Client) {
	h.mu.Lock()
	defer h.mu.Unlock()

	room, ok := h.rooms[c.RoomID]
	if !ok {
		return
	}

	if _, exists := room[c.ID]; exists {
		delete(room, c.ID)
		close(c.send)

		// Collect updated members
		members := make([]string, 0, len(room))
		for _, member := range room {
			if member.Nickname != "" {
				members = append(members, member.Nickname)
			} else {
				members = append(members, member.ID)
			}
		}

		if len(room) == 0 {
			delete(h.rooms, c.RoomID)
		} else {
			leaveMsg := Message{
				Type:      "leave",
				RoomID:    c.RoomID,
				SenderID:  c.ID,
				Nickname:  c.Nickname,
				Timestamp: time.Now().UnixMilli(),
				Members:   members,
			}
			h.broadcastToRoomLocked(c.RoomID, leaveMsg, "")
		}
	}
}

func (h *Hub) handleBroadcast(msg *Message) {
	h.mu.RLock()
	defer h.mu.RUnlock()

	room, exists := h.rooms[msg.RoomID]
	if !exists {
		return
	}

	data, err := json.Marshal(msg)
	if err != nil {
		return
	}

	for _, client := range room {
		// Do not echo "typing" indicators back to sender
		if msg.Type == "typing" && client.ID == msg.SenderID {
			continue
		}

		select {
		case client.send <- data:
		default:
			// Client buffer full or blocked; dropped to protect server memory
		}
	}
}

func (h *Hub) broadcastToRoomLocked(roomID string, msg Message, skipClientID string) {
	room, exists := h.rooms[roomID]
	if !exists {
		return
	}

	data, err := json.Marshal(msg)
	if err != nil {
		return
	}

	for id, client := range room {
		if id == skipClientID {
			continue
		}
		select {
		case client.send <- data:
		default:
		}
	}
}

// RoomCount returns the current count of active rooms in memory.
func (h *Hub) RoomCount() int {
	h.mu.RLock()
	defer h.mu.RUnlock()
	return len(h.rooms)
}

// ClientCount returns the current count of all active clients across all rooms.
func (h *Hub) ClientCount() int {
	h.mu.RLock()
	defer h.mu.RUnlock()
	total := 0
	for _, room := range h.rooms {
		total += len(room)
	}
	return total
}

// ServeWS handles incoming WebSocket connections.
func (h *Hub) ServeWS(ws *websocket.Conn) {
	defer ws.Close()

	// Initial message must be a 'join' event specifying room and nickname
	var initMsg Message
	if err := websocket.JSON.Receive(ws, &initMsg); err != nil {
		return
	}

	if initMsg.RoomID == "" {
		return
	}

	client := &Client{
		ID:       initMsg.SenderID,
		Nickname: initMsg.Nickname,
		RoomID:   initMsg.RoomID,
		ws:       ws,
		send:     make(chan []byte, 128),
		hub:      h,
	}

	h.register <- client

	// Write pump goroutine
	done := make(chan struct{})
	go func() {
		defer close(done)
		for msg := range client.send {
			if _, err := ws.Write(msg); err != nil {
				return
			}
		}
	}()

	// Read pump loop
	for {
		var msg Message
		if err := websocket.JSON.Receive(ws, &msg); err != nil {
			break
		}
		// Security enforce: room ID and sender ID must match client
		msg.RoomID = client.RoomID
		msg.SenderID = client.ID
		if msg.Nickname == "" {
			msg.Nickname = client.Nickname
		}
		if msg.Timestamp == 0 {
			msg.Timestamp = time.Now().UnixMilli()
		}

		h.broadcast <- &msg
	}

	h.unregister <- client
	<-done
}
