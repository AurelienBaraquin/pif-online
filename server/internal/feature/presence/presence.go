// Package presence shows players to each other on the overworld.
package presence

import (
	"encoding/json"

	"github.com/AurelienBaraquin/pif-online/server/internal/protocol"
	"github.com/AurelienBaraquin/pif-online/server/internal/room"
	"github.com/AurelienBaraquin/pif-online/server/internal/session"
)

type player struct {
	session    *session.Session
	appearance protocol.Appearance
	state      protocol.State
	hasState   bool
	interest   map[int]struct{}
	known      map[session.ID]struct{}
}

// Feature implements session.Feature. Every viewer tracks the players it has
// been told about, so join and leave messages always stay balanced.
type Feature struct {
	players map[session.ID]*player
	rooms   *room.Index
}

// New returns an empty presence feature.
func New() *Feature {
	return &Feature{
		players: make(map[session.ID]*player),
		rooms:   room.NewIndex(),
	}
}

// Handlers implements session.Feature.
func (f *Feature) Handlers() map[string]session.Handler {
	return map[string]session.Handler{
		protocol.TypeMove:       f.handleMove,
		protocol.TypeAppearance: f.handleAppearance,
		protocol.TypeInterest:   f.handleInterest,
	}
}

// SessionStarted implements session.Feature.
func (f *Feature) SessionStarted(s *session.Session) {
	f.players[s.ID()] = &player{
		session:  s,
		interest: make(map[int]struct{}),
		known:    make(map[session.ID]struct{}),
	}
}

// SessionEnded implements session.Feature.
func (f *Feature) SessionEnded(s *session.Session) {
	leaving, exists := f.players[s.ID()]
	if !exists {
		return
	}
	delete(f.players, s.ID())
	for mapID := range leaving.interest {
		f.rooms.Unsubscribe(mapID, s.ID())
	}
	for _, viewer := range f.players {
		if _, knows := viewer.known[s.ID()]; knows {
			delete(viewer.known, s.ID())
			viewer.session.Send(protocol.TypePlayerLeft, protocol.PlayerLeft{ID: uint32(s.ID())})
		}
	}
}

func (f *Feature) handleMove(sender *session.Session, data json.RawMessage) error {
	var state protocol.State
	if err := protocol.Decode(data, &state); err != nil {
		return err
	}
	if err := state.Validate(); err != nil {
		return err
	}
	mover := f.players[sender.ID()]
	previousMap, hadState := mover.state.Map, mover.hasState
	mover.state = state
	mover.hasState = true

	maps := []int{state.Map}
	if hadState && previousMap != state.Map {
		maps = append(maps, previousMap)
	}
	for _, id := range f.rooms.Subscribers(maps...) {
		reconcile(f.players[id], mover, true)
	}
	return nil
}

func (f *Feature) handleAppearance(sender *session.Session, data json.RawMessage) error {
	var appearance protocol.Appearance
	if err := protocol.Decode(data, &appearance); err != nil {
		return err
	}
	if err := appearance.Validate(); err != nil {
		return err
	}
	subject := f.players[sender.ID()]
	subject.appearance = appearance
	message := protocol.PlayerAppearance{ID: uint32(sender.ID()), Appearance: appearance}
	for _, viewer := range f.players {
		if _, knows := viewer.known[sender.ID()]; knows {
			viewer.session.Send(protocol.TypePlayerAppearance, message)
		}
	}
	return nil
}

func (f *Feature) handleInterest(sender *session.Session, data json.RawMessage) error {
	var interest protocol.Interest
	if err := protocol.Decode(data, &interest); err != nil {
		return err
	}
	if err := interest.Validate(); err != nil {
		return err
	}
	viewer := f.players[sender.ID()]
	for mapID := range viewer.interest {
		f.rooms.Unsubscribe(mapID, sender.ID())
	}
	viewer.interest = make(map[int]struct{}, len(interest.Maps))
	for _, mapID := range interest.Maps {
		viewer.interest[mapID] = struct{}{}
		f.rooms.Subscribe(mapID, sender.ID())
	}
	for _, subject := range f.players {
		reconcile(viewer, subject, false)
	}
	return nil
}

// reconcile brings what viewer knows about subject in line with the current
// state. When moved is false, an already visible subject sends nothing.
func reconcile(viewer, subject *player, moved bool) {
	subjectID := subject.session.ID()
	_, known := viewer.known[subjectID]
	visible := canSee(viewer, subject)
	switch {
	case visible && !known:
		viewer.known[subjectID] = struct{}{}
		viewer.session.Send(protocol.TypePlayerJoined, protocol.PlayerJoined{
			ID:         uint32(subjectID),
			Name:       subject.session.Name(),
			Appearance: subject.appearance,
			State:      subject.state,
		})
	case !visible && known:
		delete(viewer.known, subjectID)
		viewer.session.Send(protocol.TypePlayerLeft, protocol.PlayerLeft{ID: uint32(subjectID)})
	case visible && moved:
		viewer.session.Send(protocol.TypePlayerMoved, protocol.PlayerMoved{
			ID:    uint32(subjectID),
			State: subject.state,
		})
	}
}

func canSee(viewer, subject *player) bool {
	if viewer == subject || !subject.hasState {
		return false
	}
	_, interested := viewer.interest[subject.state.Map]
	return interested
}
