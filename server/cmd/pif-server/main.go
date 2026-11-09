// Command pif-server runs the PIF Online multiplayer server.
package main

import (
	"bufio"
	"context"
	"flag"
	"fmt"
	"log"
	"net"
	"os"
	"os/signal"
	"runtime"
	"syscall"

	"github.com/AurelienBaraquin/pif-online/server/internal/feature/duel"
	"github.com/AurelienBaraquin/pif-online/server/internal/feature/presence"
	"github.com/AurelienBaraquin/pif-online/server/internal/protocol"
	"github.com/AurelienBaraquin/pif-online/server/internal/session"
)

func main() {
	address := flag.String("addr", ":7777", "TCP address to listen on")
	flag.Parse()

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	listener, err := net.Listen("tcp", *address)
	if err != nil {
		fatal(fmt.Sprintf("Cannot listen on %s: %v\nIs another server already running?", *address, err))
	}
	printJoinInstructions(listener.Addr())

	config := session.DefaultConfig()
	hub := session.NewHub(config, presence.New(), duel.New(config.Clock.Now))
	hub.Serve(ctx, listener)
	log.Print("stopped")
}

// fatal reports a startup error. On Windows the server is usually started by a
// double-click, whose console would otherwise close before it can be read.
func fatal(message string) {
	fmt.Fprintln(os.Stderr, message)
	if runtime.GOOS == "windows" {
		fmt.Fprintln(os.Stderr, "Press Enter to close.")
		_, _ = bufio.NewReader(os.Stdin).ReadString('\n')
	}
	os.Exit(1)
}

func printJoinInstructions(bound net.Addr) {
	port := bound.(*net.TCPAddr).Port
	fmt.Printf("PIF Online server running (protocol %d, port %d). Keep this window open.\n", protocol.Version, port)
	interfaces, err := net.InterfaceAddrs()
	if err != nil {
		log.Printf("cannot list network addresses: %v", err)
		return
	}
	for _, address := range joinAddresses(interfaces, port) {
		fmt.Printf("  On your network, players join: %s\n", address)
	}
	fmt.Println("  Over the Internet, players use this machine's public address or domain.")
}

// joinAddresses lists the private IPv4 addresses players can type in the game.
func joinAddresses(interfaces []net.Addr, port int) []string {
	var addresses []string
	for _, candidate := range interfaces {
		network, isIP := candidate.(*net.IPNet)
		if !isIP || network.IP.To4() == nil || !network.IP.IsPrivate() {
			continue
		}
		addresses = append(addresses, net.JoinHostPort(network.IP.String(), fmt.Sprint(port)))
	}
	return addresses
}
