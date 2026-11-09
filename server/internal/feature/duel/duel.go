// Package duel arbitrates player-versus-player battles. Both clients simulate
// the same battle from a shared seed: the server only orders the flow and
// reveals a round's choices once both have arrived.
package duel

import (
	"crypto/rand"
	"encoding/binary"
	"encoding/json"
	"errors"
	"fmt"
	"time"

	"github.com/AurelienBaraquin/pif-online/server/internal/protocol"
	"github.com/AurelienBaraquin/pif-online/server/internal/session"
)

const (
	// challengeTTL bounds both the wait for an answer and the wait for parties.
	challengeTTL = 30 * time.Second
	// staleGrace is how long after a match ends its players' in-flight
	// messages are ignored rather than treated as protocol violations.
	staleGrace = 15 * time.Second
	// maxReplacementsPerRound stops a client from extending the timer forever.
	maxReplacementsPerRound = 8
	// maxPendingHashes bounds memory when one client stops reporting hashes.
	maxPendingHashes = 256
)

var errWrongState = errors.New("message not valid in this duel state")

// Feature implements session.Feature and session.Ticker.
type Feature struct {
	now     func() time.Time
	online  map[session.ID]*session.Session
	matches map[session.ID]*match
	recent  map[session.ID]time.Time
}

// New returns an empty duel feature reading the time from now.
func New(now func() time.Time) *Feature {
	return &Feature{
		now:     now,
		online:  make(map[session.ID]*session.Session),
		matches: make(map[session.ID]*match),
		recent:  make(map[session.ID]time.Time),
	}
}

// Handlers implements session.Feature.
func (f *Feature) Handlers() map[string]session.Handler {
	return map[string]session.Handler{
		protocol.TypeDuelChallenge:   f.handleChallenge,
		protocol.TypeDuelResponse:    f.handleResponse,
		protocol.TypeDuelParty:       f.handleParty,
		protocol.TypeDuelChoice:      f.handleChoice,
		protocol.TypeDuelReplacement: f.handleReplacement,
		protocol.TypeDuelHash:        f.handleHash,
		protocol.TypeDuelResult:      f.handleResult,
		protocol.TypeDuelForfeit:     f.handleForfeit,
		protocol.TypeDuelReplacing:   f.handleReplacing,
	}
}

// SessionStarted implements session.Feature.
func (f *Feature) SessionStarted(s *session.Session) {
	f.online[s.ID()] = s
}

// SessionEnded implements session.Feature.
func (f *Feature) SessionEnded(s *session.Session) {
	delete(f.online, s.ID())
	if m, engaged := f.matches[s.ID()]; engaged {
		f.abandon(m, s.ID())
	}
	delete(f.recent, s.ID())
}

// Tick implements session.Ticker.
func (f *Feature) Tick(now time.Time) {
	for _, m := range f.matches {
		if !now.Before(m.deadline) {
			f.expire(m)
		}
	}
	for id, until := range f.recent {
		if !now.Before(until) {
			delete(f.recent, id)
		}
	}
}

func (f *Feature) expire(m *match) {
	if m.phase == phaseBattle {
		f.end(m, m.timeoutWinner(), protocol.EndTimeout)
		return
	}
	f.release(m)
	decline(m.players[0], m.players[1].ID(), protocol.DeclineExpired)
	decline(m.players[1], m.players[0].ID(), protocol.DeclineExpired)
}

func (f *Feature) abandon(m *match, gone session.ID) {
	survivor := 1 - m.sideOf(gone)
	if m.phase == phaseBattle {
		f.end(m, &survivor, protocol.EndDisconnect)
		return
	}
	f.release(m)
	decline(m.players[survivor], gone, protocol.DeclineOffline)
}

func (f *Feature) release(m *match) {
	until := f.now().Add(staleGrace)
	for _, player := range m.players {
		delete(f.matches, player.ID())
		f.recent[player.ID()] = until
	}
}

func (f *Feature) end(m *match, winner *int, reason string) {
	f.release(m)
	ended := protocol.DuelEnded{Winner: winner, Reason: reason}
	for _, player := range m.players {
		player.Send(protocol.TypeDuelEnded, ended)
	}
}

func decline(to *session.Session, other session.ID, reason string) {
	to.Send(protocol.TypeDuelDeclined, protocol.DuelDeclined{Target: uint32(other), Reason: reason})
}

// matchInPhase returns the sender's match in the given phase. It returns nil
// without error for a message that was in flight when the match ended, and an
// error for a message that could never have been valid.
func (f *Feature) matchInPhase(sender *session.Session, wanted phase) (*match, error) {
	if m, engaged := f.matches[sender.ID()]; engaged && m.phase == wanted {
		return m, nil
	}
	if _, stale := f.recent[sender.ID()]; stale {
		return nil, nil
	}
	return nil, errWrongState
}

func (f *Feature) handleChallenge(sender *session.Session, data json.RawMessage) error {
	var challenge protocol.DuelChallenge
	if err := protocol.Decode(data, &challenge); err != nil {
		return err
	}
	if err := challenge.Rules.Validate(); err != nil {
		return err
	}
	targetID := session.ID(challenge.Target)
	if targetID == sender.ID() {
		return fmt.Errorf("%w: challenging oneself", protocol.ErrInvalid)
	}
	target, online := f.online[targetID]
	switch {
	case !online:
		decline(sender, targetID, protocol.DeclineOffline)
	case f.isEngaged(sender.ID()) || f.isEngaged(targetID):
		decline(sender, targetID, protocol.DeclineBusy)
	default:
		f.invite(sender, target, challenge.Rules)
	}
	return nil
}

func (f *Feature) isEngaged(id session.ID) bool {
	_, engaged := f.matches[id]
	return engaged
}

func (f *Feature) invite(challenger, target *session.Session, rules protocol.DuelRules) {
	m := newMatch(challenger, target, rules)
	m.deadline = f.now().Add(challengeTTL)
	f.matches[challenger.ID()] = m
	f.matches[target.ID()] = m
	target.Send(protocol.TypeDuelInvited, protocol.DuelInvited{
		From:  uint32(challenger.ID()),
		Name:  challenger.Name(),
		Rules: rules,
	})
}

// handleResponse ignores answers to a challenge that no longer exists: it may
// have expired while the player was reading it.
func (f *Feature) handleResponse(sender *session.Session, data json.RawMessage) error {
	var response protocol.DuelResponse
	if err := protocol.Decode(data, &response); err != nil {
		return err
	}
	m, engaged := f.matches[sender.ID()]
	if !engaged || m.phase != phaseInvited || m.sideOf(sender.ID()) != 1 ||
		uint32(m.players[0].ID()) != response.From {
		return nil
	}
	if !response.Accept {
		f.release(m)
		decline(m.players[0], sender.ID(), protocol.DeclineRefused)
		return nil
	}
	m.phase = phaseParties
	m.deadline = f.now().Add(challengeTTL)
	m.players[0].Send(protocol.TypeDuelAccepted, protocol.DuelAccepted{Opponent: uint32(m.players[1].ID())})
	m.players[1].Send(protocol.TypeDuelAccepted, protocol.DuelAccepted{Opponent: uint32(m.players[0].ID())})
	return nil
}

func (f *Feature) handleParty(sender *session.Session, data json.RawMessage) error {
	var party protocol.DuelParty
	if err := protocol.Decode(data, &party); err != nil {
		return err
	}
	m, err := f.matchInPhase(sender, phaseParties)
	if m == nil {
		return err
	}
	if err := party.Validate(m.rules); err != nil {
		return err
	}
	side := m.sideOf(sender.ID())
	if m.parties[side] != nil {
		return fmt.Errorf("%w: second party", errWrongState)
	}
	m.parties[side] = party.Party
	if m.hasBothParties() {
		return f.start(m)
	}
	return nil
}

func (f *Feature) start(m *match) error {
	seed, err := newSeed()
	if err != nil {
		return err
	}
	m.phase = phaseBattle
	m.round = 1
	m.deadline = f.now().Add(m.turnDuration())
	players := [2]protocol.DuelPlayer{
		{ID: uint32(m.players[0].ID()), Name: m.players[0].Name()},
		{ID: uint32(m.players[1].ID()), Name: m.players[1].Name()},
	}
	for side, player := range m.players {
		player.Send(protocol.TypeDuelStart, protocol.DuelStart{
			Seed:    seed,
			Side:    side,
			Rules:   m.rules,
			Players: players,
			Parties: m.parties,
		})
	}
	return nil
}

func newSeed() (uint32, error) {
	var bytes [4]byte
	if _, err := rand.Read(bytes[:]); err != nil {
		return 0, fmt.Errorf("generate seed: %w", err)
	}
	return binary.BigEndian.Uint32(bytes[:]), nil
}

func (f *Feature) handleChoice(sender *session.Session, data json.RawMessage) error {
	var choice protocol.DuelChoice
	if err := protocol.Decode(data, &choice); err != nil {
		return err
	}
	m, err := f.matchInPhase(sender, phaseBattle)
	if m == nil {
		return err
	}
	if err := choice.DuelAction.Validate(m.rules); err != nil {
		return err
	}
	side := m.sideOf(sender.ID())
	if choice.Round != m.round || m.choices[side] != nil {
		return fmt.Errorf("%w: choice for round %d in round %d", errWrongState, choice.Round, m.round)
	}
	action := choice.DuelAction
	m.choices[side] = &action
	if !m.hasBothChoices() {
		return nil
	}
	turn := m.resolveRound()
	m.deadline = f.now().Add(m.turnDuration())
	for _, player := range m.players {
		player.Send(protocol.TypeDuelTurn, turn)
	}
	return nil
}

func (f *Feature) handleReplacement(sender *session.Session, data json.RawMessage) error {
	var replacement protocol.DuelReplacement
	if err := protocol.Decode(data, &replacement); err != nil {
		return err
	}
	m, err := f.matchInPhase(sender, phaseBattle)
	if m == nil {
		return err
	}
	if err := replacement.Validate(m.rules); err != nil {
		return err
	}
	side := m.sideOf(sender.ID())
	if m.round < 2 || replacement.Seq <= m.lastSeq[side] || m.replacements[side] >= maxReplacementsPerRound {
		return fmt.Errorf("%w: replacement seq %d", errWrongState, replacement.Seq)
	}
	m.lastSeq[side] = replacement.Seq
	m.owesReplacement[side] = false
	m.replacements[side]++
	m.deadline = f.now().Add(m.turnDuration())
	replaced := protocol.DuelReplaced{Side: side, Seq: replacement.Seq, Index: replacement.Index}
	for _, player := range m.players {
		player.Send(protocol.TypeDuelReplaced, replaced)
	}
	return nil
}

func (f *Feature) handleHash(sender *session.Session, data json.RawMessage) error {
	var hash protocol.DuelHash
	if err := protocol.Decode(data, &hash); err != nil {
		return err
	}
	if err := hash.Validate(); err != nil {
		return err
	}
	m, err := f.matchInPhase(sender, phaseBattle)
	if m == nil {
		return err
	}
	side := m.sideOf(sender.ID())
	if hash.Round != m.hashed[side]+1 || hash.Round >= m.round {
		return fmt.Errorf("%w: hash for round %d", errWrongState, hash.Round)
	}
	if !m.recordHash(side, hash) || len(m.pendingHashes) > maxPendingHashes {
		f.end(m, nil, protocol.EndDesync)
	}
	return nil
}

func (f *Feature) handleResult(sender *session.Session, data json.RawMessage) error {
	var result protocol.DuelResult
	if err := protocol.Decode(data, &result); err != nil {
		return err
	}
	if err := result.Validate(); err != nil {
		return err
	}
	m, err := f.matchInPhase(sender, phaseBattle)
	if m == nil {
		return err
	}
	side := m.sideOf(sender.ID())
	if m.reported[side] {
		return fmt.Errorf("%w: second result", errWrongState)
	}
	m.reported[side] = true
	m.winners[side] = result.Winner
	if !m.reported[1-side] {
		return nil
	}
	if m.winnersAgree() {
		f.end(m, result.Winner, protocol.EndFinished)
	} else {
		f.end(m, nil, protocol.EndDesync)
	}
	return nil
}

// handleReplacing records that the sender has to pick a replacement. Only a
// client can know this, and it is trusted because it can only hurt its sender:
// a side that admits owing a replacement loses if its timer runs out.
func (f *Feature) handleReplacing(sender *session.Session, _ json.RawMessage) error {
	m, err := f.matchInPhase(sender, phaseBattle)
	if m == nil {
		return err
	}
	if m.round < 2 {
		return fmt.Errorf("%w: replacing in round %d", errWrongState, m.round)
	}
	m.owesReplacement[m.sideOf(sender.ID())] = true
	return nil
}

func (f *Feature) handleForfeit(sender *session.Session, _ json.RawMessage) error {
	m, err := f.matchInPhase(sender, phaseBattle)
	if m == nil {
		return err
	}
	winner := 1 - m.sideOf(sender.ID())
	f.end(m, &winner, protocol.EndForfeit)
	return nil
}
