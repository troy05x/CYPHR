package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/privatemsg/im-server/internal/hub"
	"golang.org/x/net/websocket"
)

func TestEndToEndWebSocketFlow(t *testing.T) {
	h := hub.NewHub()
	go h.Run()
	defer h.Close()

	mux := http.NewServeMux()
	mux.Handle("/ws", websocket.Handler(func(ws *websocket.Conn) {
		h.ServeWS(ws)
	}))

	server := httptest.NewServer(mux)
	defer server.Close()

	wsURL := "ws" + strings.TrimPrefix(server.URL, "http") + "/ws"

	// Connect Client 1 (Alice)
	origin := "http://localhost/"
	ws1, err := websocket.Dial(wsURL, "", origin)
	if err != nil {
		t.Fatalf("failed to connect client 1: %v", err)
	}
	defer ws1.Close()

	// Alice sends join
	aliceJoin := hub.Message{
		Type:      "join",
		RoomID:    "e2ee-test-room",
		SenderID:  "alice-id",
		Nickname:  "Alice",
		Timestamp: time.Now().UnixMilli(),
	}
	if err := websocket.JSON.Send(ws1, aliceJoin); err != nil {
		t.Fatalf("failed to send join for Alice: %v", err)
	}

	// Alice receives peer list
	var peerMsg hub.Message
	if err := websocket.JSON.Receive(ws1, &peerMsg); err != nil {
		t.Fatalf("alice failed to receive peers: %v", err)
	}
	if peerMsg.Type != "peers" || len(peerMsg.Members) != 1 {
		t.Fatalf("expected peers message for Alice with 1 member, got %+v", peerMsg)
	}

	// Connect Client 2 (Bob)
	ws2, err := websocket.Dial(wsURL, "", origin)
	if err != nil {
		t.Fatalf("failed to connect client 2: %v", err)
	}
	defer ws2.Close()

	bobJoin := hub.Message{
		Type:      "join",
		RoomID:    "e2ee-test-room",
		SenderID:  "bob-id",
		Nickname:  "Bob",
		Timestamp: time.Now().UnixMilli(),
	}
	if err := websocket.JSON.Send(ws2, bobJoin); err != nil {
		t.Fatalf("failed to send join for Bob: %v", err)
	}

	// Alice receives join notice for Bob
	var aliceHeardJoin hub.Message
	if err := websocket.JSON.Receive(ws1, &aliceHeardJoin); err != nil {
		t.Fatalf("alice failed to receive bob join: %v", err)
	}
	if aliceHeardJoin.Type != "join" || aliceHeardJoin.Nickname != "Bob" {
		t.Fatalf("unexpected join event: %+v", aliceHeardJoin)
	}

	// Bob sends encrypted GIF message
	gifMsg := hub.Message{
		Type:      "msg",
		RoomID:    "e2ee-test-room",
		SenderID:  "bob-id",
		Nickname:  "Bob",
		Payload:   "encrypted-aes-gcm-gif-url",
		IsGIF:     true,
		Timestamp: time.Now().UnixMilli(),
	}
	if err := websocket.JSON.Send(ws2, gifMsg); err != nil {
		t.Fatalf("failed to send message: %v", err)
	}

	// Both receive message
	var receivedMsg hub.Message
	if err := websocket.JSON.Receive(ws1, &receivedMsg); err != nil {
		t.Fatalf("alice failed to receive msg: %v", err)
	}
	if receivedMsg.Payload != "encrypted-aes-gcm-gif-url" || !receivedMsg.IsGIF {
		t.Fatalf("unexpected message received: %+v", receivedMsg)
	}
}

func TestHealthEndpoint(t *testing.T) {
	req, _ := http.NewRequest("GET", "/healthz", nil)
	rr := httptest.NewRecorder()

	h := hub.NewHub()
	handler := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.Write([]byte(`{"status":"ok","rooms":0,"clients":0,"alloc_mb":1.5}`))
	})
	handler.ServeHTTP(rr, req)

	if status := rr.Code; status != http.StatusOK {
		t.Errorf("handler returned wrong status code: got %v want %v", status, http.StatusOK)
	}

	var data map[string]interface{}
	if err := json.Unmarshal(rr.Body.Bytes(), &data); err != nil {
		t.Fatalf("invalid json: %v", err)
	}
	if data["status"] != "ok" {
		t.Errorf("expected ok status, got %v", data["status"])
	}
	_ = h
}
