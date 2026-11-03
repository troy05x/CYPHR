package hub

import (
	"encoding/json"
	"testing"
	"time"
)

func TestHubRegistrationAndPeers(t *testing.T) {
	h := NewHub()
	go h.Run()
	defer h.Close()

	client1 := &Client{
		ID:       "user-1",
		Nickname: "Alice",
		RoomID:   "secret-lounge",
		send:     make(chan []byte, 10),
		hub:      h,
	}

	h.register <- client1

	// Wait for peer list message
	select {
	case data := <-client1.send:
		var msg Message
		if err := json.Unmarshal(data, &msg); err != nil {
			t.Fatalf("failed to parse message: %v", err)
		}
		if msg.Type != "peers" {
			t.Fatalf("expected peers message, got: %s", msg.Type)
		}
		if len(msg.Members) != 1 || msg.Members[0] != "Alice" {
			t.Fatalf("unexpected members: %v", msg.Members)
		}
	case <-time.After(500 * time.Millisecond):
		t.Fatal("timed out waiting for peers message")
	}

	if h.RoomCount() != 1 {
		t.Fatalf("expected 1 room, got %d", h.RoomCount())
	}
	if h.ClientCount() != 1 {
		t.Fatalf("expected 1 client, got %d", h.ClientCount())
	}

	// Register second client
	client2 := &Client{
		ID:       "user-2",
		Nickname: "Bob",
		RoomID:   "secret-lounge",
		send:     make(chan []byte, 10),
		hub:      h,
	}
	h.register <- client2

	// client1 should receive 'join' announcement
	select {
	case data := <-client1.send:
		var msg Message
		if err := json.Unmarshal(data, &msg); err != nil {
			t.Fatalf("failed to unmarshal: %v", err)
		}
		if msg.Type != "join" || msg.Nickname != "Bob" {
			t.Fatalf("expected join event for Bob, got %+v", msg)
		}
	case <-time.After(500 * time.Millisecond):
		t.Fatal("timed out waiting for Bob's join event")
	}

	// client2 should receive 'peers' list containing both Alice and Bob
	select {
	case data := <-client2.send:
		var msg Message
		if err := json.Unmarshal(data, &msg); err != nil {
			t.Fatalf("failed to unmarshal: %v", err)
		}
		if msg.Type != "peers" || len(msg.Members) != 2 {
			t.Fatalf("expected 2 peers, got %+v", msg)
		}
	case <-time.After(500 * time.Millisecond):
		t.Fatal("timed out waiting for client2 peers")
	}

	// Broadcast encrypted payload
	broadcastMsg := &Message{
		Type:      "msg",
		RoomID:    "secret-lounge",
		SenderID:  client1.ID,
		Nickname:  client1.Nickname,
		Payload:   "ciphertext-blob-12345",
		IsGIF:     false,
		Timestamp: time.Now().UnixMilli(),
	}
	h.broadcast <- broadcastMsg

	// Both client1 and client2 should receive the broadcast
	for _, c := range []*Client{client1, client2} {
		select {
		case data := <-c.send:
			var msg Message
			if err := json.Unmarshal(data, &msg); err != nil {
				t.Fatalf("failed to parse: %v", err)
			}
			if msg.Payload != "ciphertext-blob-12345" {
				t.Fatalf("expected payload match, got: %s", msg.Payload)
			}
		case <-time.After(500 * time.Millisecond):
			t.Fatalf("client %s timed out waiting for broadcast", c.Nickname)
		}
	}

	// Unregister Alice
	h.unregister <- client1
	select {
	case data := <-client2.send:
		var msg Message
		if err := json.Unmarshal(data, &msg); err != nil {
			t.Fatalf("failed to parse: %v", err)
		}
		if msg.Type != "leave" || msg.Nickname != "Alice" {
			t.Fatalf("expected Alice leave event, got: %+v", msg)
		}
	case <-time.After(500 * time.Millisecond):
		t.Fatal("timed out waiting for Alice leave notification")
	}

	// Unregister Bob -> Room should be completely deleted from memory
	h.unregister <- client2
	time.Sleep(50 * time.Millisecond)

	if h.RoomCount() != 0 {
		t.Fatalf("expected 0 rooms after last member left, got %d", h.RoomCount())
	}
}
