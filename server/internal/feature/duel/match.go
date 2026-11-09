package duel

import (
	"time"

	"github.com/AurelienBaraquin/pif-online/server/internal/protocol"
	"github.com/AurelienBaraquin/pif-online/server/internal/session"
)

type phase int

const (
	phaseInvited phase = iota
	phaseParties
	phaseBattle
)

// match is a challenge and, once accepted, its duel. Index 0 of every array is
// the challenger's side.
type match struct {
	players  [2]*session.Session
	rules    protocol.DuelRules
	phase    phase
	deadline time.Time

	parties     [2][]protocol.Pokemon
	appearances [2]protocol.Appearance

	round        int
	choices      [2]*protocol.DuelAction
	lastSeq      [2]int
	replacements [2]int
	// owesReplacement holds each side's own admission that it must replace.
	owesReplacement [2]bool

	hashed        [2]int
	pendingHashes map[int]string

	reported [2]bool
	winners  [2]*int
}

func newMatch(challenger, target *session.Session, rules protocol.DuelRules) *match {
	return &match{
		players:       [2]*session.Session{challenger, target},
		rules:         rules,
		lastSeq:       [2]int{-1, -1},
		pendingHashes: make(map[int]string),
	}
}

func (m *match) sideOf(id session.ID) int {
	if m.players[0].ID() == id {
		return 0
	}
	return 1
}

func (m *match) turnDuration() time.Duration {
	return time.Duration(m.rules.TurnSeconds) * time.Second
}

// resolvingDuration bounds a round still being animated: the turn timer only
// starts once both clients report that the round is over.
func (m *match) resolvingDuration() time.Duration {
	return m.turnDuration() + animationAllowance
}

// bothHashedRound reports whether both sides finished the last resolved round.
func (m *match) bothHashedRound() bool {
	return m.hashed[0] == m.round-1 && m.hashed[1] == m.round-1
}

func (m *match) hasBothParties() bool {
	return m.parties[0] != nil && m.parties[1] != nil
}

func (m *match) hasBothChoices() bool {
	return m.choices[0] != nil && m.choices[1] != nil
}

// resolveRound clears the current choices, moves to the next round and
// returns what was chosen.
func (m *match) resolveRound() protocol.DuelTurn {
	turn := protocol.DuelTurn{
		Round:   m.round,
		Choices: [2]protocol.DuelAction{*m.choices[0], *m.choices[1]},
	}
	m.round++
	m.choices = [2]*protocol.DuelAction{}
	m.replacements = [2]int{}
	m.owesReplacement = [2]bool{}
	return turn
}

// recordHash stores a side's hash for a round and reports whether it agrees
// with the other side's, when that one is already known.
func (m *match) recordHash(side int, hash protocol.DuelHash) bool {
	m.hashed[side] = hash.Round
	if m.hashed[1-side] < hash.Round {
		m.pendingHashes[hash.Round] = hash.Hash
		return true
	}
	expected := m.pendingHashes[hash.Round]
	delete(m.pendingHashes, hash.Round)
	return expected == hash.Hash
}

func (m *match) winnersAgree() bool {
	first, second := m.winners[0], m.winners[1]
	if first == nil || second == nil {
		return first == second
	}
	return *first == *second
}

// hasActed reports whether a side owes nothing to the current round.
func (m *match) hasActed(side int) bool {
	return m.choices[side] != nil || m.reported[side]
}

// timeoutWinner returns the other side when exactly one side admitted owing a
// replacement, else the only side that acted, or nil when none or both did.
func (m *match) timeoutWinner() *int {
	if m.owesReplacement[0] != m.owesReplacement[1] {
		side := 0
		if m.owesReplacement[0] {
			side = 1
		}
		return &side
	}
	first, second := m.hasActed(0), m.hasActed(1)
	if first == second {
		return nil
	}
	side := 0
	if second {
		side = 1
	}
	return &side
}
