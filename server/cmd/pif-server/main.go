// Command pif-server runs the PIF Online multiplayer server.
package main

import (
	"context"
	"flag"
	"log"
	"net"
	"os"
	"os/signal"
	"syscall"

	"github.com/AurelienBaraquin/pif-online/server/internal/feature/presence"
	"github.com/AurelienBaraquin/pif-online/server/internal/session"
)

func main() {
	address := flag.String("addr", ":7777", "TCP address to listen on")
	flag.Parse()

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	listener, err := net.Listen("tcp", *address)
	if err != nil {
		log.Fatalf("listen: %v", err)
	}
	log.Printf("listening on %s", listener.Addr())

	hub := session.NewHub(session.DefaultConfig(), presence.New())
	hub.Serve(ctx, listener)
	log.Print("stopped")
}
