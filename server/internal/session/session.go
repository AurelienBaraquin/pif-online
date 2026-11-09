// Package session owns connected clients and routes their messages to features.
package session

import (
	"log"
	"time"

	"github.com/AurelienBaraquin/pif-online/server/internal/protocol"
	"github.com/AurelienBaraquin/pif-online/server/internal/transport"
)

// ID identifies a session for the lifetime of the server process.
type ID uint32

// Session is one connected client. It is only used from the hub goroutine.
type Session struct {
	id      ID
	name    string
	conn    *transport.Conn
	started bool
	closing bool
	tokens  float64
	refill  time.Time
}

// ID returns the session's identifier.
func (s *Session) ID() ID { return s.id }

// Name returns the player name given at handshake.
func (s *Session) Name() string { return s.name }

// Send delivers a message. A failure closes the session asynchronously.
func (s *Session) Send(msgType string, payload interface{}) {
	frame, err := protocol.Encode(msgType, payload)
	if err != nil {
		log.Printf("session %d: %v", s.id, err)
		return
	}
	s.conn.Send(frame)
}

func (s *Session) kick(code, message string) {
	if s.closing {
		return
	}
	s.closing = true
	frame, err := protocol.Encode(protocol.TypeError, protocol.ErrorInfo{Code: code, Message: message})
	if err != nil {
		log.Printf("session %d: %v", s.id, err)
		s.conn.Close()
		return
	}
	s.conn.SendFinal(frame)
}

// allow spends one token from the session's rate limiter.
func (s *Session) allow(now time.Time, perSecond, burst float64) bool {
	s.tokens += now.Sub(s.refill).Seconds() * perSecond
	if s.tokens > burst {
		s.tokens = burst
	}
	s.refill = now
	if s.tokens < 1 {
		return false
	}
	s.tokens--
	return true
}
