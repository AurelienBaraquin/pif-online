package presence_test

import (
	"bufio"
	"context"
	"encoding/json"
	"fmt"
	"net"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/AurelienBaraquin/pif-online/server/internal/feature/presence"
	"github.com/AurelienBaraquin/pif-online/server/internal/protocol"
	"github.com/AurelienBaraquin/pif-online/server/internal/session"
)

const readTimeout = 3 * time.Second

type testServer struct {
	address string
}

func startServer(t *testing.T, config session.Config) testServer {
	t.Helper()
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan struct{})
	hub := session.NewHub(config, presence.New())
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
	return testServer{address: listener.Addr().String()}
}

type testClient struct {
	t      *testing.T
	conn   net.Conn
	reader *bufio.Reader
	id     uint32
}

func dial(t *testing.T, server testServer) *testClient {
	t.Helper()
	conn, err := net.Dial("tcp", server.address)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { conn.Close() })
	return &testClient{t: t, conn: conn, reader: bufio.NewReader(conn)}
}

func join(t *testing.T, server testServer, name string) *testClient {
	t.Helper()
	client := dial(t, server)
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
	_ = c.conn.SetReadDeadline(time.Now().Add(readTimeout))
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

func (c *testClient) expectClosedWith(code string) {
	c.t.Helper()
	var info protocol.ErrorInfo
	c.expect(protocol.TypeError, &info)
	if info.Code != code {
		c.t.Fatalf("code = %s, want %s", info.Code, code)
	}
	_ = c.conn.SetReadDeadline(time.Now().Add(readTimeout))
	if _, err := c.reader.ReadBytes('\n'); err == nil {
		c.t.Fatal("connection stayed open")
	}
}

// sync waits for every earlier message from this client to be processed.
func (c *testClient) sync() {
	c.t.Helper()
	c.send(protocol.TypePing, nil)
	c.expect(protocol.TypePong, nil)
}

func state(mapID, x int) protocol.State {
	return protocol.State{Map: mapID, X: x, Y: 5, Dir: 2, Speed: 3}
}

func TestPlayerOnInterestingMapJoinsThenMoves(t *testing.T) {
	server := startServer(t, session.DefaultConfig())
	alice, bob := join(t, server, "Alice"), join(t, server, "Bob")
	alice.send(protocol.TypeInterest, protocol.Interest{Maps: []int{1}})
	alice.sync()

	bob.send(protocol.TypeMove, state(1, 3))
	bob.send(protocol.TypeMove, state(1, 4))

	var joined protocol.PlayerJoined
	alice.expect(protocol.TypePlayerJoined, &joined)
	if joined.ID != bob.id || joined.Name != "Bob" || joined.State != state(1, 3) {
		t.Fatalf("joined = %+v", joined)
	}
	var moved protocol.PlayerMoved
	alice.expect(protocol.TypePlayerMoved, &moved)
	if moved.ID != bob.id || moved.State != state(1, 4) {
		t.Fatalf("moved = %+v", moved)
	}
}

func TestPlayerDoesNotSeeItself(t *testing.T) {
	server := startServer(t, session.DefaultConfig())
	alice := join(t, server, "Alice")
	alice.send(protocol.TypeInterest, protocol.Interest{Maps: []int{1}})
	alice.send(protocol.TypeMove, state(1, 1))

	alice.sync()
}

func TestInterestRevealsPlayersAlreadyThere(t *testing.T) {
	server := startServer(t, session.DefaultConfig())
	alice, bob := join(t, server, "Alice"), join(t, server, "Bob")
	bob.send(protocol.TypeMove, state(7, 2))
	bob.sync()

	alice.send(protocol.TypeInterest, protocol.Interest{Maps: []int{7}})

	var joined protocol.PlayerJoined
	alice.expect(protocol.TypePlayerJoined, &joined)
	if joined.ID != bob.id {
		t.Fatalf("joined = %+v", joined)
	}
}

func TestDroppingInterestHidesPlayer(t *testing.T) {
	server := startServer(t, session.DefaultConfig())
	alice, bob := join(t, server, "Alice"), join(t, server, "Bob")
	bob.send(protocol.TypeMove, state(7, 2))
	bob.sync()
	alice.send(protocol.TypeInterest, protocol.Interest{Maps: []int{7}})
	alice.expect(protocol.TypePlayerJoined, nil)

	alice.send(protocol.TypeInterest, protocol.Interest{Maps: []int{8}})

	var left protocol.PlayerLeft
	alice.expect(protocol.TypePlayerLeft, &left)
	if left.ID != bob.id {
		t.Fatalf("left = %+v", left)
	}
}

func TestMovingToAnotherMapHidesPlayerFromOldViewers(t *testing.T) {
	server := startServer(t, session.DefaultConfig())
	alice, bob := join(t, server, "Alice"), join(t, server, "Bob")
	alice.send(protocol.TypeInterest, protocol.Interest{Maps: []int{1}})
	alice.sync()
	bob.send(protocol.TypeMove, state(1, 1))
	alice.expect(protocol.TypePlayerJoined, nil)

	bob.send(protocol.TypeMove, state(2, 1))

	alice.expect(protocol.TypePlayerLeft, nil)
}

func TestPlayerCrossingBetweenWatchedMapsOnlyMoves(t *testing.T) {
	server := startServer(t, session.DefaultConfig())
	alice, bob := join(t, server, "Alice"), join(t, server, "Bob")
	alice.send(protocol.TypeInterest, protocol.Interest{Maps: []int{1, 2}})
	alice.sync()
	bob.send(protocol.TypeMove, state(1, 1))
	alice.expect(protocol.TypePlayerJoined, nil)

	bob.send(protocol.TypeMove, state(2, 1))

	var moved protocol.PlayerMoved
	alice.expect(protocol.TypePlayerMoved, &moved)
	if moved.State.Map != 2 {
		t.Fatalf("moved = %+v", moved)
	}
}

func TestDisconnectNotifiesViewers(t *testing.T) {
	server := startServer(t, session.DefaultConfig())
	alice, bob := join(t, server, "Alice"), join(t, server, "Bob")
	alice.send(protocol.TypeInterest, protocol.Interest{Maps: []int{1}})
	alice.sync()
	bob.send(protocol.TypeMove, state(1, 1))
	alice.expect(protocol.TypePlayerJoined, nil)

	bob.conn.Close()

	var left protocol.PlayerLeft
	alice.expect(protocol.TypePlayerLeft, &left)
	if left.ID != bob.id {
		t.Fatalf("left = %+v", left)
	}
}

func TestAppearanceReachesViewersAndNewcomers(t *testing.T) {
	server := startServer(t, session.DefaultConfig())
	alice, bob := join(t, server, "Alice"), join(t, server, "Bob")
	alice.send(protocol.TypeInterest, protocol.Interest{Maps: []int{1}})
	alice.sync()
	bob.send(protocol.TypeMove, state(1, 1))
	alice.expect(protocol.TypePlayerJoined, nil)

	bob.send(protocol.TypeAppearance, protocol.Appearance{Skin: 4})

	var changed protocol.PlayerAppearance
	alice.expect(protocol.TypePlayerAppearance, &changed)
	if changed.Appearance.Skin != 4 {
		t.Fatalf("changed = %+v", changed)
	}
	carol := join(t, server, "Carol")
	carol.send(protocol.TypeInterest, protocol.Interest{Maps: []int{1}})
	var joined protocol.PlayerJoined
	carol.expect(protocol.TypePlayerJoined, &joined)
	if joined.Appearance.Skin != 4 {
		t.Fatalf("joined = %+v", joined)
	}
}

func TestHandshakeFailures(t *testing.T) {
	server := startServer(t, session.DefaultConfig())
	cases := []struct {
		name string
		line string
		code string
	}{
		{"wrong protocol version", `{"t":"hello","d":{"v":999,"name":"A"}}`, protocol.CodeVersionMismatch},
		{"not json", `not json`, protocol.CodeBadMessage},
		{"message before hello", `{"t":"move","d":{}}`, protocol.CodeBadMessage},
		{"hello without payload", `{"t":"hello"}`, protocol.CodeBadMessage},
		{"invalid name", `{"t":"hello","d":{"v":1,"name":""}}`, protocol.CodeBadMessage},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			client := dial(t, server)
			client.raw(tc.line)
			client.expectClosedWith(tc.code)
		})
	}
}

func TestInvalidMessagesDisconnectOnlyTheSender(t *testing.T) {
	cases := []struct {
		name string
		line string
	}{
		{"unknown type", `{"t":"nope"}`},
		{"out of range state", `{"t":"move","d":{"map":0,"x":0,"y":0,"dir":2,"speed":3}}`},
		{"wrong payload type", `{"t":"move","d":"x"}`},
		{"missing payload", `{"t":"move"}`},
		{"path traversal", `{"t":"appearance","d":{"hat":".."}}`},
		{"oversized interest", `{"t":"interest","d":{"maps":[1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17]}}`},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			server := startServer(t, session.DefaultConfig())
			witness, attacker := join(t, server, "Witness"), join(t, server, "Attacker")

			attacker.raw(tc.line)

			attacker.expectClosedWith(protocol.CodeBadMessage)
			witness.sync()
		})
	}
}

func TestOversizedLineClosesConnection(t *testing.T) {
	server := startServer(t, session.DefaultConfig())
	client := join(t, server, "A")

	client.raw(strings.Repeat("x", protocol.MaxFrameBytes+10))

	_ = client.conn.SetReadDeadline(time.Now().Add(readTimeout))
	if _, err := client.reader.ReadBytes('\n'); err == nil {
		t.Fatal("connection stayed open")
	}
}

func TestFloodIsRateLimited(t *testing.T) {
	config := session.DefaultConfig()
	config.MessagesPerSecond = 1
	config.MessageBurst = 2
	server := startServer(t, config)
	client := dial(t, server)
	client.send(protocol.TypeHello, protocol.Hello{Version: protocol.Version, Name: "A"})
	client.expect(protocol.TypeWelcome, nil)

	client.send(protocol.TypePing, nil)
	client.send(protocol.TypePing, nil)
	client.send(protocol.TypePing, nil)

	client.expect(protocol.TypePong, nil)
	client.expectClosedWith(protocol.CodeRateLimited)
}

func TestFullServerRejectsNewSessions(t *testing.T) {
	config := session.DefaultConfig()
	config.MaxSessions = 1
	server := startServer(t, config)
	join(t, server, "A")

	client := dial(t, server)

	client.expectClosedWith(protocol.CodeServerFull)
}

func TestManyPlayersMovingConcurrently(t *testing.T) {
	const players, moves = 50, 40
	server := startServer(t, session.DefaultConfig())
	observer := join(t, server, "Observer")
	observer.send(protocol.TypeInterest, protocol.Interest{Maps: []int{1}})
	observer.sync()

	var group sync.WaitGroup
	for i := 0; i < players; i++ {
		client := join(t, server, fmt.Sprintf("P%d", i))
		group.Add(1)
		go func(c *testClient) {
			defer group.Done()
			for x := 0; x < moves; x++ {
				frame, _ := protocol.Encode(protocol.TypeMove, state(1, x))
				_, _ = fmt.Fprintf(c.conn, "%s\n", frame)
			}
		}(client)
	}
	group.Wait()

	counts := map[string]int{}
	for received := 0; received < players*moves; received++ {
		_ = observer.conn.SetReadDeadline(time.Now().Add(readTimeout))
		line, err := observer.reader.ReadBytes('\n')
		if err != nil {
			t.Fatalf("after %d messages: %v", received, err)
		}
		var envelope protocol.Envelope
		if err := json.Unmarshal(line, &envelope); err != nil {
			t.Fatal(err)
		}
		counts[envelope.Type]++
	}
	if counts[protocol.TypePlayerJoined] != players {
		t.Fatalf("counts = %v", counts)
	}
}
