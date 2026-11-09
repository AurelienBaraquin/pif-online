// Package transport frames newline-delimited messages over a TCP connection.
package transport

import (
	"bufio"
	"io"
	"net"
	"sync"
	"time"

	"github.com/AurelienBaraquin/pif-online/server/internal/protocol"
)

const (
	outboxSize   = 256
	writeTimeout = 5 * time.Second
)

type outgoing struct {
	data []byte
	last bool
}

// Conn reads from one goroutine and never blocks its senders: a peer too slow
// to drain its outbox is disconnected.
type Conn struct {
	raw     net.Conn
	scanner *bufio.Scanner
	idle    time.Duration
	outbox  chan outgoing
	done    chan struct{}
	once    sync.Once
}

// New starts the writer of a connection that closes after idle silence.
func New(raw net.Conn, idle time.Duration) *Conn {
	scanner := bufio.NewScanner(raw)
	scanner.Buffer(make([]byte, 0, 4096), protocol.MaxFrameBytes+1)
	conn := &Conn{
		raw:     raw,
		scanner: scanner,
		idle:    idle,
		outbox:  make(chan outgoing, outboxSize),
		done:    make(chan struct{}),
	}
	go conn.writeLoop()
	return conn
}

// ReadFrame returns the next line. The slice is valid until the next call.
func (c *Conn) ReadFrame() ([]byte, error) {
	if err := c.raw.SetReadDeadline(time.Now().Add(c.idle)); err != nil {
		return nil, err
	}
	if c.scanner.Scan() {
		return c.scanner.Bytes(), nil
	}
	if err := c.scanner.Err(); err != nil {
		return nil, err
	}
	return nil, io.EOF
}

// Send queues a line and closes the connection if the outbox is full.
func (c *Conn) Send(frame []byte) {
	c.enqueue(outgoing{data: appendNewline(frame)})
}

// SendFinal queues a line, then closes the connection once it is written.
func (c *Conn) SendFinal(frame []byte) {
	c.enqueue(outgoing{data: appendNewline(frame), last: true})
}

// Close releases the connection. It is safe to call more than once.
func (c *Conn) Close() {
	c.once.Do(func() {
		close(c.done)
		_ = c.raw.Close()
	})
}

// Done is closed once the connection is closed.
func (c *Conn) Done() <-chan struct{} {
	return c.done
}

func (c *Conn) enqueue(item outgoing) {
	select {
	case c.outbox <- item:
	case <-c.done:
	default:
		c.Close()
	}
}

func (c *Conn) writeLoop() {
	for {
		select {
		case <-c.done:
			return
		case item := <-c.outbox:
			if !c.write(item.data) || item.last {
				c.Close()
				return
			}
		}
	}
}

func (c *Conn) write(data []byte) bool {
	if err := c.raw.SetWriteDeadline(time.Now().Add(writeTimeout)); err != nil {
		return false
	}
	_, err := c.raw.Write(data)
	return err == nil
}

func appendNewline(frame []byte) []byte {
	line := make([]byte, len(frame)+1)
	copy(line, frame)
	line[len(frame)] = '\n'
	return line
}
