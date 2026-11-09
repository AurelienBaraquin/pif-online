package protocol

import (
	"encoding/json"
	"fmt"
	"regexp"
	"strings"
	"unicode"
	"unicode/utf8"
)

// Duel message types.
const (
	TypeDuelChallenge   = "duel_challenge"
	TypeDuelResponse    = "duel_response"
	TypeDuelParty       = "duel_party"
	TypeDuelChoice      = "duel_choice"
	TypeDuelReplacement = "duel_replacement"
	TypeDuelHash        = "duel_hash"
	TypeDuelResult      = "duel_result"
	TypeDuelForfeit     = "duel_forfeit"
	TypeDuelReplacing   = "duel_replacing"
	TypeDuelReject      = "duel_reject"

	TypeDuelInvited  = "duel_invited"
	TypeDuelDeclined = "duel_declined"
	TypeDuelAccepted = "duel_accepted"
	TypeDuelStart    = "duel_start"
	TypeDuelTurn     = "duel_turn"
	TypeDuelReplaced = "duel_replaced"
	TypeDuelEnded    = "duel_ended"
)

// Reasons for a duel_declined message.
const (
	DeclineRefused = "refused"
	DeclineBusy    = "busy"
	DeclineOffline = "offline"
	DeclineExpired = "expired"
)

// Reasons for a duel_ended message.
const (
	EndForfeit    = "forfeit"
	EndDisconnect = "disconnect"
	EndTimeout    = "timeout"
	EndDesync     = "desync"
	EndFinished   = "finished"
	EndIllegal    = "illegal_party"
)

// Actions a player can choose for a round.
const (
	ActionMove   = "move"
	ActionSwitch = "switch"
)

const (
	maxPartySize       = 6
	maxLevel           = 100
	minTurnSeconds     = 30
	maxTurnSeconds     = 300
	maxForm            = 99
	maxGender          = 2
	maxAbilityIndex    = 5
	maxHappiness       = 255
	statCount          = 6
	maxIV              = 31
	maxEV              = 252
	maxEVTotal         = 510
	maxMoves           = 4
	maxMovePP          = 255
	maxMovePPUp        = 3
	maxPokemonNameRune = 24
	maxHashRunes       = 64
	sideCount          = 2
)

var (
	symbolPattern = regexp.MustCompile(`^[A-Za-z0-9_]{1,32}$`)
	spritePattern = regexp.MustCompile(`^[A-Za-z0-9_.-]{1,64}$`)
)

func invalid(what string) error {
	return fmt.Errorf("%w: %s", ErrInvalid, what)
}

// Decode unmarshals a message payload.
func Decode(data json.RawMessage, target interface{}) error {
	if err := json.Unmarshal(data, target); err != nil {
		return fmt.Errorf("decode payload: %w", err)
	}
	return nil
}

// DuelRules are the constraints a challenger sets for a duel.
type DuelRules struct {
	PartySize   int  `json:"party_size"`
	Level       int  `json:"level"`
	HeldItems   bool `json:"held_items"`
	TurnSeconds int  `json:"turn_seconds"`
	// Clauses are the optional rules in force, by id: see duelClauses.
	Clauses []string `json:"clauses"`
}

// Validate checks that the rules are within the protocol's bounds.
func (r DuelRules) Validate() error {
	if r.PartySize < 1 || r.PartySize > maxPartySize {
		return invalid("party size")
	}
	if r.Level < 0 || r.Level > maxLevel {
		return invalid("rule level")
	}
	if r.TurnSeconds < minTurnSeconds || r.TurnSeconds > maxTurnSeconds {
		return invalid("turn seconds")
	}
	return r.validateClauses()
}

// DuelChallenge asks another player for a duel.
type DuelChallenge struct {
	Target uint32    `json:"target"`
	Rules  DuelRules `json:"rules"`
}

// DuelResponse answers a challenge.
type DuelResponse struct {
	From   uint32 `json:"from"`
	Accept bool   `json:"accept"`
}

// PokemonMove is one known move.
type PokemonMove struct {
	ID   string `json:"id"`
	PP   int    `json:"pp"`
	PPUp int    `json:"ppup"`
}

// Pokemon is everything a client needs to rebuild the other side's Pokémon.
type Pokemon struct {
	Species         string        `json:"species"`
	Level           int           `json:"level"`
	Form            int           `json:"form"`
	PersonalID      uint32        `json:"personal_id"`
	Gender          int           `json:"gender"`
	Nature          string        `json:"nature"`
	Ability         *string       `json:"ability"`
	AbilityIndex    *int          `json:"ability_index"`
	Item            *string       `json:"item"`
	Happiness       int           `json:"happiness"`
	IV              []int         `json:"iv"`
	IVMaxed         []bool        `json:"iv_maxed"`
	EV              []int         `json:"ev"`
	Moves           []PokemonMove `json:"moves"`
	Name            string        `json:"name"`
	Shiny           bool          `json:"shiny"`
	HeadShiny       bool          `json:"head_shiny"`
	BodyShiny       bool          `json:"body_shiny"`
	HiddenPowerType *string       `json:"hidden_power_type"`
	SizeCategory    *string       `json:"size_category"`
	PifSprite       *string       `json:"pif_sprite"`
}

func validSymbol(value *string) bool {
	return value == nil || symbolPattern.MatchString(*value)
}

func validDisplayName(name string, maxRunes int) bool {
	count := utf8.RuneCountInString(name)
	if !utf8.ValidString(name) || count < 1 || count > maxRunes {
		return false
	}
	for _, r := range name {
		if unicode.IsControl(r) {
			return false
		}
	}
	return true
}

func (p Pokemon) validateIdentity() error {
	if !symbolPattern.MatchString(p.Species) || !symbolPattern.MatchString(p.Nature) {
		return invalid("species or nature")
	}
	for _, symbol := range []*string{p.Ability, p.Item, p.HiddenPowerType, p.SizeCategory} {
		if !validSymbol(symbol) {
			return invalid("symbol")
		}
	}
	if !validDisplayName(p.Name, maxPokemonNameRune) {
		return invalid("pokemon name")
	}
	if p.PifSprite != nil && (!spritePattern.MatchString(*p.PifSprite) || strings.Contains(*p.PifSprite, "..")) {
		return invalid("sprite")
	}
	return nil
}

func (p Pokemon) validateNumbers() error {
	inBounds := p.Level >= 1 && p.Level <= maxLevel &&
		p.Form >= 0 && p.Form <= maxForm &&
		p.Gender >= 0 && p.Gender <= maxGender &&
		p.Happiness >= 0 && p.Happiness <= maxHappiness
	if !inBounds {
		return invalid("pokemon numbers")
	}
	if p.AbilityIndex != nil && (*p.AbilityIndex < 0 || *p.AbilityIndex > maxAbilityIndex) {
		return invalid("ability index")
	}
	return nil
}

func (p Pokemon) validateStats() error {
	if len(p.IV) != statCount || len(p.IVMaxed) != statCount || len(p.EV) != statCount {
		return invalid("stat count")
	}
	total := 0
	for i := 0; i < statCount; i++ {
		if p.IV[i] < 0 || p.IV[i] > maxIV || p.EV[i] < 0 || p.EV[i] > maxEV {
			return invalid("stat value")
		}
		total += p.EV[i]
	}
	if total > maxEVTotal {
		return invalid("ev total")
	}
	return nil
}

func (p Pokemon) validateMoves() error {
	if len(p.Moves) < 1 || len(p.Moves) > maxMoves {
		return invalid("move count")
	}
	for _, move := range p.Moves {
		valid := symbolPattern.MatchString(move.ID) &&
			move.PP >= 0 && move.PP <= maxMovePP &&
			move.PPUp >= 0 && move.PPUp <= maxMovePPUp
		if !valid {
			return invalid("move")
		}
	}
	return nil
}

func (p Pokemon) validateAgainst(rules DuelRules) error {
	if !rules.HeldItems && p.Item != nil {
		return invalid("held item forbidden")
	}
	if rules.Level != 0 && p.Level != rules.Level {
		return invalid("level differs from rules")
	}
	return nil
}

// Validate checks one Pokémon: the other client will load it.
func (p Pokemon) Validate(rules DuelRules) error {
	checks := []func() error{p.validateIdentity, p.validateNumbers, p.validateStats, p.validateMoves}
	for _, check := range checks {
		if err := check(); err != nil {
			return err
		}
	}
	return p.validateAgainst(rules)
}

// DuelParty is the team a player brings to a duel.
type DuelParty struct {
	Party      []Pokemon  `json:"party"`
	Appearance Appearance `json:"appearance"`
}

// Validate checks the party's size and every member against the rules.
func (p DuelParty) Validate(rules DuelRules) error {
	if len(p.Party) != rules.PartySize {
		return invalid("party length")
	}
	for _, pokemon := range p.Party {
		if err := pokemon.Validate(rules); err != nil {
			return err
		}
	}
	if err := rules.checkClauses(p.Party); err != nil {
		return err
	}
	return p.Appearance.Validate()
}

// DuelAction is what a player does in a round.
type DuelAction struct {
	Action string `json:"action"`
	Index  int    `json:"index"`
}

// Validate checks the action and its index for a party of the given rules.
func (a DuelAction) Validate(rules DuelRules) error {
	switch a.Action {
	case ActionMove:
		if a.Index < 0 || a.Index >= maxMoves {
			return invalid("move index")
		}
	case ActionSwitch:
		if a.Index < 0 || a.Index >= rules.PartySize {
			return invalid("switch index")
		}
	default:
		return invalid("action")
	}
	return nil
}

// DuelChoice is a player's action for one round.
type DuelChoice struct {
	Round int `json:"round"`
	DuelAction
}

// DuelReplacement replaces a fainted or switched-out Pokémon.
type DuelReplacement struct {
	Seq   int `json:"seq"`
	Index int `json:"index"`
}

// Validate checks the sequence number and the party slot.
func (r DuelReplacement) Validate(rules DuelRules) error {
	if r.Seq < 0 || r.Index < 0 || r.Index >= rules.PartySize {
		return invalid("replacement")
	}
	return nil
}

// DuelHash reports the state hash a client computed after a round.
type DuelHash struct {
	Round int    `json:"round"`
	Hash  string `json:"hash"`
}

// Validate checks the round number and the hash's length.
func (h DuelHash) Validate() error {
	count := utf8.RuneCountInString(h.Hash)
	if h.Round < 1 || count < 1 || count > maxHashRunes {
		return invalid("hash")
	}
	return nil
}

// DuelResult is the outcome a client computed. A nil winner is a draw.
type DuelResult struct {
	Winner *int `json:"winner"`
}

// Validate checks that the winner is a side or nil.
func (r DuelResult) Validate() error {
	if r.Winner != nil && (*r.Winner < 0 || *r.Winner >= sideCount) {
		return invalid("winner")
	}
	return nil
}

// DuelInvited tells a player about a challenge.
type DuelInvited struct {
	From  uint32    `json:"from"`
	Name  string    `json:"name"`
	Rules DuelRules `json:"rules"`
}

// DuelDeclined cancels a challenge. Target is the other player involved.
type DuelDeclined struct {
	Target uint32 `json:"target"`
	Reason string `json:"reason"`
}

// DuelAccepted asks both players of an accepted challenge for their party.
type DuelAccepted struct {
	Opponent uint32 `json:"opponent"`
}

// DuelPlayer identifies one side of a duel.
type DuelPlayer struct {
	ID         uint32     `json:"id"`
	Name       string     `json:"name"`
	Appearance Appearance `json:"appearance"`
}

// DuelStart begins a duel. Players and Parties are in side order.
type DuelStart struct {
	Seed    uint32        `json:"seed"`
	Side    int           `json:"side"`
	Rules   DuelRules     `json:"rules"`
	Players [2]DuelPlayer `json:"players"`
	Parties [2][]Pokemon  `json:"parties"`
}

// DuelTurn reveals a round's choices, in side order.
type DuelTurn struct {
	Round   int           `json:"round"`
	Choices [2]DuelAction `json:"choices"`
}

// DuelReplaced forwards a replacement to both players.
type DuelReplaced struct {
	Side  int `json:"side"`
	Seq   int `json:"seq"`
	Index int `json:"index"`
}

// DuelEnded closes a duel. A nil winner means no side won.
type DuelEnded struct {
	Winner *int   `json:"winner"`
	Reason string `json:"reason"`
}
