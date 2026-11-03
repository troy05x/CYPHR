package main

import (
	"embed"
	"flag"
	"fmt"
	"io/fs"
	"log"
	"net/http"
	"os"
	"runtime"
	"runtime/debug"
	"time"

	"github.com/privatemsg/im-server/internal/hub"
	"golang.org/x/net/websocket"
)

//go:embed static/*
var staticFiles embed.FS

func main() {
	port := flag.Int("port", 8080, "HTTP/WebSocket listening port")
	flag.Parse()

	if envPort := os.Getenv("PORT"); envPort != "" {
		fmt.Sscanf(envPort, "%d", port)
	}

	// Optimize Go garbage collector for 1GB RAM constraint.
	// Target ~20MB GC target so the server remains ultra-lightweight.
	debug.SetGCPercent(50)
	debug.SetMemoryLimit(128 * 1024 * 1024) // 128 MB soft limit ceiling

	h := hub.NewHub()
	go h.Run()
	defer h.Close()

	mux := http.NewServeMux()

	// WebSocket endpoint
	mux.Handle("/ws", websocket.Handler(func(ws *websocket.Conn) {
		h.ServeWS(ws)
	}))

	// Static assets embedded directly in binary - zero external file I/O runtime overhead
	subFS, err := fs.Sub(staticFiles, "static")
	if err != nil {
		log.Fatalf("failed to read embedded static directory: %v", err)
	}
	mux.Handle("/", http.FileServer(http.FS(subFS)))

	// Health & lightweight metrics endpoint (for systemd / monitoring / reverse proxy healthchecks)
	mux.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
		var m runtime.MemStats
		runtime.ReadMemStats(&m)
		w.Header().Set("Content-Type", "application/json")
		fmt.Fprintf(w, `{"status":"ok","rooms":%d,"clients":%d,"alloc_mb":%.2f,"sys_mb":%.2f}`+"\n",
			h.RoomCount(),
			h.ClientCount(),
			float64(m.Alloc)/(1024*1024),
			float64(m.Sys)/(1024*1024),
		)
	})

	server := &http.Server{
		Addr:              fmt.Sprintf(":%d", *port),
		Handler:           mux,
		ReadHeaderTimeout: 5 * time.Second,
		IdleTimeout:       120 * time.Second,
	}

	log.Printf("[IM-SERVER] Privacy IM Server listening on http://0.0.0.0:%d (Memory optimized for 1GB VPS)", *port)
	if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
		log.Fatalf("[IM-SERVER] Server failed: %v", err)
	}
}
