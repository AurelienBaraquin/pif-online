package session

import (
	"context"
	"net"
	"testing"
	"time"
)

type stubClock struct {
	ticks chan time.Time
}

func (c stubClock) Now() time.Time { return time.Time{} }

func (c stubClock) Ticks() (<-chan time.Time, func()) { return c.ticks, func() {} }

type plainFeature struct{}

func (plainFeature) Handlers() map[string]Handler { return nil }
func (plainFeature) SessionStarted(*Session)      {}
func (plainFeature) SessionEnded(*Session)        {}

type tickingFeature struct {
	plainFeature
	received chan time.Time
}

func (f tickingFeature) Tick(now time.Time) { f.received <- now }

func TestTickReachesOnlyFeaturesImplementingTicker(t *testing.T) {
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	clock := stubClock{ticks: make(chan time.Time)}
	config := DefaultConfig()
	config.Clock = clock
	ticking := tickingFeature{received: make(chan time.Time, 1)}
	hub := NewHub(config, plainFeature{}, ticking)
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan struct{})
	go func() {
		defer close(done)
		hub.Serve(ctx, listener)
	}()
	defer func() {
		cancel()
		<-done
	}()
	sent := time.Unix(1000, 0)

	clock.ticks <- sent

	select {
	case got := <-ticking.received:
		if !got.Equal(sent) {
			t.Fatalf("tick = %v, want %v", got, sent)
		}
	case <-time.After(3 * time.Second):
		t.Fatal("tick not delivered")
	}
}

func TestSystemClockTicks(t *testing.T) {
	ticks, stop := SystemClock{Interval: time.Millisecond}.Ticks()
	defer stop()

	select {
	case <-ticks:
	case <-time.After(3 * time.Second):
		t.Fatal("no tick")
	}
}
