package duel_test

import (
	"bufio"
	"context"
	"encoding/json"
	"fmt"
	"net"
	"sync"
	"testing"
	"time"

	"github.com/AurelienBaraquin/pif-online/server/internal/feature/duel"
	"github.com/AurelienBaraquin/pif-online/server/internal/protocol"
	"github.com/AurelienBaraquin/pif-online/server/internal/session"
)

const ioTimeout = 3 * time.Second

// fakeClock only moves when a test advances it. Ticks are unbuffered, so once
// Advance returns the hub has taken the tick and handles it before any later
// message.
type fakeClock struct {
	t     *testing.T
	mu    sync.Mutex
	now   time.Time
	ticks chan time.Time
}

func (c *fakeClock) Now() time.Time {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.now
}

func (c *fakeClock) Ticks() (<-chan time.Time, func()) { return c.ticks, func() {} }

func (c *fakeClock) advance(d time.Duration) {
	c.t.Helper()
	c.mu.Lock()
	c.now = c.now.Add(d)
	now := c.now
	c.mu.Unlock()
	select {
	case c.ticks <- now:
	case <-time.After(ioTimeout):
		c.t.Fatal("hub did not take the tick")
	}
}

type testServer struct {
	address string
	clock   *fakeClock
}

func startServer(t *testing.T) testServer {
	t.Helper()
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	clock := &fakeClock{t: t, now: time.Unix(1000, 0), ticks: make(chan time.Time)}
	config := session.DefaultConfig()
	config.Clock = clock
	hub := session.NewHub(config, duel.New(clock.Now))
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan struct{})
	go func() {
		defer close(done)
		hub.Serve(ctx, listener)
	}()
	t.Cleanup(func() {
		cancel()
		select {
		case <-done:
		case <-time.After(5 * time.Second):
			t.Error("server did not stop")
		}
	})
	return testServer{address: listener.Addr().String(), clock: clock}
}

type testClient struct {
	t      *testing.T
	conn   net.Conn
	reader *bufio.Reader
	id     uint32
}

func join(t *testing.T, server testServer, name string) *testClient {
	t.Helper()
	conn, err := net.Dial("tcp", server.address)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { conn.Close() })
	client := &testClient{t: t, conn: conn, reader: bufio.NewReaderSize(conn, protocol.MaxFrameBytes)}
	client.send(protocol.TypeHello, protocol.Hello{Version: protocol.Version, Name: name})
	var welcome protocol.Welcome
	client.expect(protocol.TypeWelcome, &welcome)
	client.id = welcome.ID
	return client
}

func (c *testClient) send(msgType string, payload interface{}) {
	c.t.Helper()
	frame, err := protocol.Encode(msgType, payload)
	if err != nil {
		c.t.Fatal(err)
	}
	c.raw(string(frame))
}

func (c *testClient) raw(line string) {
	c.t.Helper()
	if _, err := fmt.Fprintf(c.conn, "%s\n", line); err != nil {
		c.t.Fatal(err)
	}
}

func (c *testClient) expect(msgType string, target interface{}) {
	c.t.Helper()
	_ = c.conn.SetReadDeadline(time.Now().Add(ioTimeout))
	line, err := c.reader.ReadBytes('\n')
	if err != nil {
		c.t.Fatalf("waiting for %s: %v", msgType, err)
	}
	var envelope protocol.Envelope
	if err := json.Unmarshal(line, &envelope); err != nil {
		c.t.Fatal(err)
	}
	if envelope.Type != msgType {
		c.t.Fatalf("got %s, want %s", line, msgType)
	}
	if target != nil {
		if err := json.Unmarshal(envelope.Data, target); err != nil {
			c.t.Fatal(err)
		}
	}
}

func (c *testClient) expectKicked() {
	c.t.Helper()
	var info protocol.ErrorInfo
	c.expect(protocol.TypeError, &info)
	if info.Code != protocol.CodeBadMessage {
		c.t.Fatalf("code = %s", info.Code)
	}
	_ = c.conn.SetReadDeadline(time.Now().Add(ioTimeout))
	if _, err := c.reader.ReadBytes('\n'); err == nil {
		c.t.Fatal("connection stayed open")
	}
}

// sync waits for this client's earlier messages to be processed, and proves
// that none of them produced a reply.
func (c *testClient) sync() {
	c.t.Helper()
	c.send(protocol.TypePing, nil)
	c.expect(protocol.TypePong, nil)
}

func (c *testClient) expectEnded(reason string, winner *int) {
	c.t.Helper()
	var ended protocol.DuelEnded
	c.expect(protocol.TypeDuelEnded, &ended)
	sameWinner := (ended.Winner == nil) == (winner == nil) &&
		(winner == nil || *ended.Winner == *winner)
	if ended.Reason != reason || !sameWinner {
		c.t.Fatalf("ended = %+v, want %s winner %v", ended, reason, winner)
	}
}

func (c *testClient) expectDeclined(target uint32, reason string) {
	c.t.Helper()
	var declined protocol.DuelDeclined
	c.expect(protocol.TypeDuelDeclined, &declined)
	if declined != (protocol.DuelDeclined{Target: target, Reason: reason}) {
		c.t.Fatalf("declined = %+v", declined)
	}
}

func side(value int) *int { return &value }

var testRules = protocol.DuelRules{PartySize: 1, HeldItems: true, TurnSeconds: 60, Format: protocol.FormatSingles}

func testParty() protocol.DuelParty {
	return protocol.DuelParty{Party: []protocol.Pokemon{{
		Species: "PIKACHU", Level: 50, Nature: "HARDY",
		IV: make([]int, 6), IVMaxed: make([]bool, 6), EV: make([]int, 6),
		Moves: []protocol.PokemonMove{{ID: "TACKLE", PP: 35}},
		Name:  "Pika",
	}}}
}

// challenge leaves bob holding an invitation from alice.
func challenge(alice, bob *testClient) {
	alice.t.Helper()
	alice.send(protocol.TypeDuelChallenge, protocol.DuelChallenge{Target: bob.id, Rules: testRules})
	bob.expect(protocol.TypeDuelInvited, nil)
}

// accept leaves both players expected to send a party.
func accept(alice, bob *testClient) {
	alice.t.Helper()
	challenge(alice, bob)
	bob.send(protocol.TypeDuelResponse, protocol.DuelResponse{From: alice.id, Accept: true})
	alice.expect(protocol.TypeDuelAccepted, nil)
	bob.expect(protocol.TypeDuelAccepted, nil)
}

// begin brings two players into round 1 of a duel, alice on side 0.
func begin(alice, bob *testClient) {
	alice.t.Helper()
	accept(alice, bob)
	alice.send(protocol.TypeDuelParty, testParty())
	bob.send(protocol.TypeDuelParty, testParty())
	alice.expect(protocol.TypeDuelStart, nil)
	bob.expect(protocol.TypeDuelStart, nil)
}

func choose(client *testClient, round int) {
	client.t.Helper()
	client.send(protocol.TypeDuelChoice, protocol.DuelChoice{
		Round:   round,
		Actions: []protocol.DuelAction{{Action: protocol.ActionMove, Index: 0}},
	})
}

// playRound resolves one round.
func playRound(alice, bob *testClient, round int) {
	alice.t.Helper()
	choose(alice, round)
	choose(bob, round)
	alice.expect(protocol.TypeDuelTurn, nil)
	bob.expect(protocol.TypeDuelTurn, nil)
}
