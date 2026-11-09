package transport

import (
	"bufio"
	"bytes"
	"errors"
	"net"
	"testing"
	"time"

	"github.com/AurelienBaraquin/pif-online/server/internal/protocol"
)

func TestReadFrameRejectsOversizedLine(t *testing.T) {
	client, server := net.Pipe()
	defer client.Close()
	conn := New(server, time.Second)
	defer conn.Close()
	go func() { _, _ = client.Write(bytes.Repeat([]byte("x"), protocol.MaxFrameBytes+2)) }()

	_, err := conn.ReadFrame()

	if !errors.Is(err, bufio.ErrTooLong) {
		t.Fatalf("err = %v", err)
	}
}

func TestReadFrameTimesOutWhenIdle(t *testing.T) {
	client, server := net.Pipe()
	defer client.Close()
	conn := New(server, 10*time.Millisecond)
	defer conn.Close()

	_, err := conn.ReadFrame()

	var netErr net.Error
	if !errors.As(err, &netErr) || !netErr.Timeout() {
		t.Fatalf("err = %v", err)
	}
}

func TestSendFinalDeliversThenCloses(t *testing.T) {
	client, server := net.Pipe()
	defer client.Close()
	conn := New(server, time.Second)

	conn.SendFinal([]byte("bye"))

	reader := bufio.NewReader(client)
	line, err := reader.ReadString('\n')
	if err != nil || line != "bye\n" {
		t.Fatalf("line = %q, err = %v", line, err)
	}
	select {
	case <-conn.Done():
	case <-time.After(time.Second):
		t.Fatal("connection stayed open")
	}
}

func TestSendClosesSlowPeerInsteadOfBlocking(t *testing.T) {
	client, server := net.Pipe()
	defer client.Close()
	conn := New(server, time.Second)

	for i := 0; i < outboxSize*2; i++ {
		conn.Send([]byte("x"))
	}

	select {
	case <-conn.Done():
	case <-time.After(time.Second):
		t.Fatal("slow peer was not disconnected")
	}
}
