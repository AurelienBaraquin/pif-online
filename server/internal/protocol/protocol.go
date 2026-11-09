// Package protocol defines the messages described in protocol/PROTOCOL.md.
package protocol

import (
	"encoding/json"
	"errors"
	"fmt"
	"regexp"
	"strings"
	"unicode"
	"unicode/utf8"
)

// Version must match PROTOCOL_VERSION in the client's core/001_config.rb.
const Version = 1

// MaxFrameBytes is the largest accepted line, excluding its newline.
const MaxFrameBytes = 16 * 1024

// Message types.
const (
	TypeHello            = "hello"
	TypePing             = "ping"
	TypePong             = "pong"
	TypeWelcome          = "welcome"
	TypeError            = "error"
	TypeMove             = "move"
	TypeAppearance       = "appearance"
	TypeInterest         = "interest"
	TypePlayerJoined     = "player_joined"
	TypePlayerMoved      = "player_moved"
	TypePlayerAppearance = "player_appearance"
	TypePlayerLeft       = "player_left"
)

// Error codes sent to clients before a connection closes.
const (
	CodeVersionMismatch = "version_mismatch"
	CodeBadMessage      = "bad_message"
	CodeServerFull      = "server_full"
	CodeRateLimited     = "rate_limited"
)

const (
	maxNameRunes   = 32
	maxMapID       = 9999
	maxCoordinate  = 9999
	maxSpeed       = 6
	maxSkin        = 99
	maxColorShift  = 1000000
	maxInterestSet = 16
)

var (
	assetNamePattern = regexp.MustCompile(`^[A-Za-z0-9_ .-]{1,64}$`)

	// ErrInvalid reports a well-formed message with out-of-range content.
	ErrInvalid = errors.New("invalid message content")
)

// Envelope is the outer shape of every message.
type Envelope struct {
	Type string          `json:"t"`
	Data json.RawMessage `json:"d,omitempty"`
}

// Hello opens a session.
type Hello struct {
	Version int    `json:"v"`
	Name    string `json:"name"`
}

// Validate checks the content of a Hello, except its version.
func (h Hello) Validate() error {
	count := utf8.RuneCountInString(h.Name)
	if !utf8.ValidString(h.Name) || count < 1 || count > maxNameRunes {
		return fmt.Errorf("%w: name length", ErrInvalid)
	}
	for _, r := range h.Name {
		if unicode.IsControl(r) {
			return fmt.Errorf("%w: name character", ErrInvalid)
		}
	}
	return nil
}

// Welcome accepts a session.
type Welcome struct {
	ID uint32 `json:"id"`
}

// ErrorInfo explains an imminent close.
type ErrorInfo struct {
	Code    string `json:"code"`
	Message string `json:"message"`
}

// State is a player's position on the overworld.
type State struct {
	Map   int `json:"map"`
	X     int `json:"x"`
	Y     int `json:"y"`
	Dir   int `json:"dir"`
	Speed int `json:"speed"`
}

// Validate checks that a State is within the protocol's bounds.
func (s State) Validate() error {
	inBounds := s.Map >= 1 && s.Map <= maxMapID &&
		s.X >= 0 && s.X <= maxCoordinate &&
		s.Y >= 0 && s.Y <= maxCoordinate &&
		s.Speed >= 1 && s.Speed <= maxSpeed
	validDir := s.Dir == 2 || s.Dir == 4 || s.Dir == 6 || s.Dir == 8
	if !inBounds || !validDir {
		return fmt.Errorf("%w: state", ErrInvalid)
	}
	return nil
}

// Appearance describes how a player is drawn.
type Appearance struct {
	Skin         int     `json:"skin"`
	Clothes      *string `json:"clothes"`
	Hair         *string `json:"hair"`
	Hat          *string `json:"hat"`
	Hat2         *string `json:"hat2"`
	ClothesColor int     `json:"clothes_color"`
	HairColor    int     `json:"hair_color"`
	HatColor     int     `json:"hat_color"`
	Hat2Color    int     `json:"hat2_color"`
}

// Validate rejects values that could escape the outfit folders on a client.
func (a Appearance) Validate() error {
	if a.Skin < 0 || a.Skin > maxSkin {
		return fmt.Errorf("%w: skin", ErrInvalid)
	}
	for _, asset := range []*string{a.Clothes, a.Hair, a.Hat, a.Hat2} {
		if asset != nil && !validAssetName(*asset) {
			return fmt.Errorf("%w: asset name", ErrInvalid)
		}
	}
	for _, color := range []int{a.ClothesColor, a.HairColor, a.HatColor, a.Hat2Color} {
		if color < -maxColorShift || color > maxColorShift {
			return fmt.Errorf("%w: color", ErrInvalid)
		}
	}
	return nil
}

func validAssetName(name string) bool {
	return assetNamePattern.MatchString(name) && !strings.Contains(name, "..")
}

// Interest lists the maps a client displays.
type Interest struct {
	Maps []int `json:"maps"`
}

// Validate checks the size of the set and each map id.
func (i Interest) Validate() error {
	if len(i.Maps) > maxInterestSet {
		return fmt.Errorf("%w: too many maps", ErrInvalid)
	}
	for _, id := range i.Maps {
		if id < 1 || id > maxMapID {
			return fmt.Errorf("%w: map id", ErrInvalid)
		}
	}
	return nil
}

// PlayerJoined announces a newly visible player.
type PlayerJoined struct {
	ID         uint32     `json:"id"`
	Name       string     `json:"name"`
	Appearance Appearance `json:"appearance"`
	State      State      `json:"state"`
}

// PlayerMoved updates a visible player's position.
type PlayerMoved struct {
	ID    uint32 `json:"id"`
	State State  `json:"state"`
}

// PlayerAppearance updates a visible player's look.
type PlayerAppearance struct {
	ID         uint32     `json:"id"`
	Appearance Appearance `json:"appearance"`
}

// PlayerLeft removes a player from view.
type PlayerLeft struct {
	ID uint32 `json:"id"`
}

// Encode builds a line, without its newline, for a type and optional payload.
func Encode(msgType string, payload interface{}) ([]byte, error) {
	envelope := Envelope{Type: msgType}
	if payload != nil {
		data, err := json.Marshal(payload)
		if err != nil {
			return nil, fmt.Errorf("encode %s payload: %w", msgType, err)
		}
		envelope.Data = data
	}
	frame, err := json.Marshal(envelope)
	if err != nil {
		return nil, fmt.Errorf("encode %s: %w", msgType, err)
	}
	return frame, nil
}
