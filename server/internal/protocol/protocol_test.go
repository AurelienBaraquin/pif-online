package protocol

import (
	"os"
	"regexp"
	"strconv"
	"strings"
	"testing"
)

func text(value string) *string { return &value }

func TestHelloValidateGameBuild(t *testing.T) {
	cases := map[string]bool{"ab12": true, "": false, "AB12": false, "../x": false, strings.Repeat("a", maxGameBuildLength+1): false}
	for build, valid := range cases {
		if err := (Hello{Name: "Red", Game: build}).Validate(); (err == nil) != valid {
			t.Fatalf("Validate(game %q) = %v", build, err)
		}
	}
}

func TestHelloValidate(t *testing.T) {
	cases := []struct {
		name  string
		input string
		valid bool
	}{
		{"accepts a plain name", "Red", true},
		{"accepts accents", "Aurélien", true},
		{"rejects empty", "", false},
		{"rejects control characters", "a\nb", false},
		{"rejects over 32 characters", strings.Repeat("x", 33), false},
		{"rejects invalid UTF-8", "\xff", false},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if err := (Hello{Name: tc.input, Game: "ab12"}).Validate(); (err == nil) != tc.valid {
				t.Fatalf("Validate(%q) = %v", tc.input, err)
			}
		})
	}
}

func TestStateValidate(t *testing.T) {
	valid := State{Map: 1, X: 0, Y: 9999, Dir: 8, Speed: 6}
	if err := valid.Validate(); err != nil {
		t.Fatalf("valid state rejected: %v", err)
	}
	invalid := []State{
		{Map: 0, Dir: 2, Speed: 3},
		{Map: 10000, Dir: 2, Speed: 3},
		{Map: 1, X: -1, Dir: 2, Speed: 3},
		{Map: 1, Y: 10000, Dir: 2, Speed: 3},
		{Map: 1, Dir: 3, Speed: 3},
		{Map: 1, Dir: 2, Speed: 0},
		{Map: 1, Dir: 2, Speed: 7},
	}
	for _, state := range invalid {
		if state.Validate() == nil {
			t.Errorf("state %+v accepted", state)
		}
	}
}

func TestAppearanceValidate(t *testing.T) {
	cases := []struct {
		name       string
		appearance Appearance
		valid      bool
	}{
		{"accepts empty values", Appearance{}, true},
		{"accepts asset names", Appearance{Hair: text("1_painter"), Hat: text("snorlax hat-2.a")}, true},
		{"rejects a parent path", Appearance{Hat: text("..")}, false},
		{"rejects dots hidden in a name", Appearance{Hat: text("a..b")}, false},
		{"rejects slashes", Appearance{Clothes: text("a/b")}, false},
		{"rejects backslashes", Appearance{Clothes: text(`a\b`)}, false},
		{"rejects an empty name", Appearance{Hat2: text("")}, false},
		{"rejects negative skin", Appearance{Skin: -1}, false},
		{"rejects huge color", Appearance{HairColor: maxColorShift + 1}, false},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if err := tc.appearance.Validate(); (err == nil) != tc.valid {
				t.Fatalf("Validate() = %v", err)
			}
		})
	}
}

func TestInterestValidate(t *testing.T) {
	if err := (Interest{Maps: []int{1, 9999}}).Validate(); err != nil {
		t.Fatalf("valid interest rejected: %v", err)
	}
	if (Interest{Maps: make([]int, maxInterestSet+1)}).Validate() == nil {
		t.Fatal("oversized interest accepted")
	}
	if (Interest{Maps: []int{0}}).Validate() == nil {
		t.Fatal("map id 0 accepted")
	}
}

func TestEncodeOmitsAbsentPayload(t *testing.T) {
	frame, err := Encode(TypePong, nil)
	if err != nil {
		t.Fatal(err)
	}
	if string(frame) != `{"t":"pong"}` {
		t.Fatalf("got %s", frame)
	}
}

func TestClientAndDocumentUseServerVersion(t *testing.T) {
	sources := map[string]*regexp.Regexp{
		"../../../client/998_Multiplayer/core/001_config.rb": regexp.MustCompile(`PROTOCOL_VERSION = (\d+)`),
		"../../../protocol/PROTOCOL.md":                      regexp.MustCompile(`Version: \*\*(\d+)\*\*`),
	}
	for path, pattern := range sources {
		content, err := os.ReadFile(path)
		if err != nil {
			t.Fatal(err)
		}
		match := pattern.FindSubmatch(content)
		if match == nil {
			t.Fatalf("%s: version not found", path)
		}
		if version, _ := strconv.Atoi(string(match[1])); version != Version {
			t.Errorf("%s declares version %d, server has %d", path, version, Version)
		}
	}
}
