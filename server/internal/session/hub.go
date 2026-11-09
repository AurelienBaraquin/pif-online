package session

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"net"
	"sync"
	"time"

	"github.com/AurelienBaraquin/pif-online/server/internal/protocol"
	"github.com/AurelienBaraquin/pif-online/server/internal/transport"
)

const (
	eventQueueSize = 1024
	minAcceptDelay = 10 * time.Millisecond
	maxAcceptDelay = time.Second
	tickInterval   = time.Second
)

// Handler processes one message. An error disconnects the sender.
type Handler func(sender *Session, data json.RawMessage) error

// Feature is a self-contained gameplay module. All methods run on the hub
// goroutine, so features need no locking.
type Feature interface {
	Handlers() map[string]Handler
	SessionStarted(s *Session)
	SessionEnded(s *Session)
}

// Ticker is an optional extension of Feature for time-driven behaviour. Tick
// runs on the hub goroutine at the pace of the configured Clock.
type Ticker interface {
	Tick(now time.Time)
}

// Clock tells the time and paces the hub's ticks.
type Clock interface {
	Now() time.Time
	// Ticks returns the tick channel and the function that releases it.
	Ticks() (ticks <-chan time.Time, stop func())
}

// SystemClock is the wall clock, ticking every Interval.
type SystemClock struct {
	Interval time.Duration
}

// Now implements Clock.
func (c SystemClock) Now() time.Time { return time.Now() }

// Ticks implements Clock.
func (c SystemClock) Ticks() (<-chan time.Time, func()) {
	ticker := time.NewTicker(c.Interval)
	return ticker.C, ticker.Stop
}

// Config sets the hub's limits.
type Config struct {
	MaxSessions       int
	IdleTimeout       time.Duration
	MessagesPerSecond float64
	MessageBurst      float64
	Clock             Clock
}

// DefaultConfig returns the limits used in production.
func DefaultConfig() Config {
	return Config{
		MaxSessions:       256,
		IdleTimeout:       15 * time.Second,
		MessagesPerSecond: 60,
		MessageBurst:      120,
		Clock:             SystemClock{Interval: tickInterval},
	}
}

type eventKind int

const (
	eventConnected eventKind = iota
	eventFrame
	eventClosed
)

type event struct {
	kind    eventKind
	session *Session
	frame   []byte
}

// Hub serializes every session change and message on a single goroutine.
type Hub struct {
	config   Config
	features []Feature
	tickers  []Ticker
	handlers map[string]Handler
	sessions map[*Session]struct{}
	events   chan event
	nextID   ID
}

// NewHub wires features together. Two features claiming the same message type
// is a programming error and panics at startup.
func NewHub(config Config, features ...Feature) *Hub {
	handlers := make(map[string]Handler)
	var tickers []Ticker
	for _, feature := range features {
		if ticker, ticks := feature.(Ticker); ticks {
			tickers = append(tickers, ticker)
		}
		for msgType, handler := range feature.Handlers() {
			if _, duplicate := handlers[msgType]; duplicate {
				panic(fmt.Sprintf("duplicate handler for message type %q", msgType))
			}
			handlers[msgType] = handler
		}
	}
	return &Hub{
		config:   config,
		features: features,
		tickers:  tickers,
		handlers: handlers,
		sessions: make(map[*Session]struct{}),
		events:   make(chan event, eventQueueSize),
	}
}

// Serve accepts connections until ctx is cancelled, then closes every session.
func (h *Hub) Serve(ctx context.Context, listener net.Listener) {
	var readers sync.WaitGroup
	hubDone := make(chan struct{})
	go func() {
		defer close(hubDone)
		h.run(ctx)
	}()
	go func() {
		<-ctx.Done()
		_ = listener.Close()
	}()

	h.accept(ctx, listener, &readers)
	<-hubDone
	readers.Wait()
}

// accept runs until the listener closes. Other failures, such as running out
// of file descriptors, are retried so that connected players stay online.
func (h *Hub) accept(ctx context.Context, listener net.Listener, readers *sync.WaitGroup) {
	delay := minAcceptDelay
	for {
		raw, err := listener.Accept()
		if err != nil {
			if ctx.Err() != nil || errors.Is(err, net.ErrClosed) {
				return
			}
			log.Printf("accept: %v (retrying in %s)", err, delay)
			select {
			case <-time.After(delay):
			case <-ctx.Done():
				return
			}
			delay *= 2
			if delay > maxAcceptDelay {
				delay = maxAcceptDelay
			}
			continue
		}
		delay = minAcceptDelay
		session := &Session{
			conn:   transport.New(raw, h.config.IdleTimeout),
			tokens: h.config.MessageBurst,
			refill: time.Now(),
		}
		readers.Add(1)
		go func() {
			defer readers.Done()
			h.read(ctx, session)
		}()
		go closeOnCancel(ctx, session)
	}
}

func closeOnCancel(ctx context.Context, s *Session) {
	select {
	case <-ctx.Done():
		s.conn.Close()
	case <-s.conn.Done():
	}
}

func (h *Hub) read(ctx context.Context, s *Session) {
	if !h.publish(ctx, event{kind: eventConnected, session: s}) {
		s.conn.Close()
		return
	}
	for {
		frame, err := s.conn.ReadFrame()
		if err != nil {
			h.publish(ctx, event{kind: eventClosed, session: s})
			return
		}
		copied := append([]byte(nil), frame...)
		if !h.publish(ctx, event{kind: eventFrame, session: s, frame: copied}) {
			return
		}
	}
}

func (h *Hub) publish(ctx context.Context, e event) bool {
	select {
	case h.events <- e:
		return true
	case <-ctx.Done():
		return false
	}
}

func (h *Hub) run(ctx context.Context) {
	ticks, stop := h.config.Clock.Ticks()
	defer stop()
	for {
		select {
		case <-ctx.Done():
			return
		case e := <-h.events:
			h.handle(e)
		case now := <-ticks:
			for _, ticker := range h.tickers {
				ticker.Tick(now)
			}
		}
	}
}

func (h *Hub) handle(e event) {
	switch e.kind {
	case eventConnected:
		h.register(e.session)
	case eventFrame:
		h.receive(e.session, e.frame)
	case eventClosed:
		h.unregister(e.session)
	}
}

func (h *Hub) register(s *Session) {
	if len(h.sessions) >= h.config.MaxSessions {
		s.kick(protocol.CodeServerFull, "The server is full.")
		return
	}
	h.sessions[s] = struct{}{}
}

func (h *Hub) unregister(s *Session) {
	s.conn.Close()
	if _, known := h.sessions[s]; !known {
		return
	}
	delete(h.sessions, s)
	if !s.started {
		return
	}
	for _, feature := range h.features {
		feature.SessionEnded(s)
	}
}

func (h *Hub) receive(s *Session, frame []byte) {
	if s.closing {
		return
	}
	if !s.allow(time.Now(), h.config.MessagesPerSecond, h.config.MessageBurst) {
		s.kick(protocol.CodeRateLimited, "Too many messages.")
		return
	}
	var envelope protocol.Envelope
	if err := json.Unmarshal(frame, &envelope); err != nil {
		s.kick(protocol.CodeBadMessage, "Malformed message.")
		return
	}
	if !s.started {
		h.handshake(s, envelope)
		return
	}
	h.dispatch(s, envelope)
}

func (h *Hub) handshake(s *Session, envelope protocol.Envelope) {
	var hello protocol.Hello
	if envelope.Type != protocol.TypeHello || json.Unmarshal(envelope.Data, &hello) != nil {
		s.kick(protocol.CodeBadMessage, "Expected hello.")
		return
	}
	if hello.Version != protocol.Version {
		s.kick(protocol.CodeVersionMismatch, fmt.Sprintf("Server protocol is %d.", protocol.Version))
		return
	}
	if hello.Validate() != nil {
		s.kick(protocol.CodeBadMessage, "Invalid hello.")
		return
	}
	h.nextID++
	s.id = h.nextID
	s.name = hello.Name
	s.game = hello.Game
	s.started = true
	s.Send(protocol.TypeWelcome, protocol.Welcome{ID: uint32(s.id)})
	for _, feature := range h.features {
		feature.SessionStarted(s)
	}
}

func (h *Hub) dispatch(s *Session, envelope protocol.Envelope) {
	if envelope.Type == protocol.TypePing {
		s.Send(protocol.TypePong, nil)
		return
	}
	handler, known := h.handlers[envelope.Type]
	if !known {
		s.kick(protocol.CodeBadMessage, "Unknown message type.")
		return
	}
	if err := handler(s, envelope.Data); err != nil {
		log.Printf("session %d (%s): %s: %v", s.id, s.name, envelope.Type, err)
		s.kick(protocol.CodeBadMessage, "Invalid message content.")
	}
}
