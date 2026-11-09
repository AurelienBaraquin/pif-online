package protocol

import (
	"encoding/json"
	"strings"
	"testing"
)

var openRules = DuelRules{PartySize: 1, HeldItems: true, TurnSeconds: 60}

func number(value int) *int { return &value }

func validPokemon() Pokemon {
	return Pokemon{
		Species: "PIKACHU", Level: 50, Gender: 1, Nature: "HARDY",
		IV: make([]int, 6), IVMaxed: make([]bool, 6), EV: make([]int, 6),
		Moves: []PokemonMove{{ID: "TACKLE", PP: 35}},
		Name:  "Pika",
	}
}

func TestDuelRulesValidate(t *testing.T) {
	cases := []struct {
		name  string
		rules DuelRules
		valid bool
	}{
		{"accepts bounds", DuelRules{PartySize: 6, Level: 100, TurnSeconds: 300}, true},
		{"accepts unchanged level", DuelRules{PartySize: 1, TurnSeconds: 30}, true},
		{"rejects empty party", DuelRules{TurnSeconds: 30}, false},
		{"rejects large party", DuelRules{PartySize: 7, TurnSeconds: 30}, false},
		{"rejects level above max", DuelRules{PartySize: 1, Level: 101, TurnSeconds: 30}, false},
		{"rejects negative level", DuelRules{PartySize: 1, Level: -1, TurnSeconds: 30}, false},
		{"rejects short turn", DuelRules{PartySize: 1, TurnSeconds: 29}, false},
		{"rejects long turn", DuelRules{PartySize: 1, TurnSeconds: 301}, false},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if err := tc.rules.Validate(); (err == nil) != tc.valid {
				t.Fatalf("Validate() = %v", err)
			}
		})
	}
}

func TestPokemonValidate(t *testing.T) {
	cases := []struct {
		name   string
		mutate func(*Pokemon)
		rules  DuelRules
		valid  bool
	}{
		{"accepts a plain pokemon", func(p *Pokemon) {}, openRules, true},
		{"accepts a sprite", func(p *Pokemon) { p.PifSprite = text("12.34a-b_c") }, openRules, true},
		{"accepts an item", func(p *Pokemon) { p.Item = text("LEFTOVERS") }, openRules, true},
		{"accepts 510 evs", func(p *Pokemon) { p.EV = []int{252, 252, 6, 0, 0, 0} }, openRules, true},
		{"rejects bad species", func(p *Pokemon) { p.Species = "A B" }, openRules, false},
		{"rejects long species", func(p *Pokemon) { p.Species = strings.Repeat("A", 33) }, openRules, false},
		{"rejects level 0", func(p *Pokemon) { p.Level = 0 }, openRules, false},
		{"rejects level 101", func(p *Pokemon) { p.Level = 101 }, openRules, false},
		{"rejects form", func(p *Pokemon) { p.Form = 100 }, openRules, false},
		{"rejects gender", func(p *Pokemon) { p.Gender = 3 }, openRules, false},
		{"rejects happiness", func(p *Pokemon) { p.Happiness = 256 }, openRules, false},
		{"rejects ability index", func(p *Pokemon) { p.AbilityIndex = number(6) }, openRules, false},
		{"rejects bad ability", func(p *Pokemon) { p.Ability = text("a/b") }, openRules, false},
		{"rejects five ivs", func(p *Pokemon) { p.IV = make([]int, 5) }, openRules, false},
		{"rejects iv value", func(p *Pokemon) { p.IV[0] = 32 }, openRules, false},
		{"rejects five maxed", func(p *Pokemon) { p.IVMaxed = make([]bool, 5) }, openRules, false},
		{"rejects ev value", func(p *Pokemon) { p.EV[0] = 253 }, openRules, false},
		{"rejects ev total", func(p *Pokemon) { p.EV = []int{252, 252, 7, 0, 0, 0} }, openRules, false},
		{"rejects no moves", func(p *Pokemon) { p.Moves = nil }, openRules, false},
		{"rejects five moves", func(p *Pokemon) { p.Moves = make([]PokemonMove, 5) }, openRules, false},
		{"rejects pp", func(p *Pokemon) { p.Moves[0].PP = 256 }, openRules, false},
		{"rejects ppup", func(p *Pokemon) { p.Moves[0].PPUp = 4 }, openRules, false},
		{"rejects empty name", func(p *Pokemon) { p.Name = "" }, openRules, false},
		{"rejects long name", func(p *Pokemon) { p.Name = strings.Repeat("é", 25) }, openRules, false},
		{"rejects control in name", func(p *Pokemon) { p.Name = "a\nb" }, openRules, false},
		{"rejects sprite traversal", func(p *Pokemon) { p.PifSprite = text("a..b") }, openRules, false},
		{"rejects sprite slash", func(p *Pokemon) { p.PifSprite = text("a/b") }, openRules, false},
		{"rejects forbidden item", func(p *Pokemon) { p.Item = text("LEFTOVERS") }, DuelRules{PartySize: 1, TurnSeconds: 60}, false},
		{"rejects level differing from rules", func(p *Pokemon) {}, DuelRules{PartySize: 1, Level: 10, HeldItems: true, TurnSeconds: 60}, false},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			pokemon := validPokemon()
			tc.mutate(&pokemon)
			if err := pokemon.Validate(tc.rules); (err == nil) != tc.valid {
				t.Fatalf("Validate() = %v", err)
			}
		})
	}
}

func TestPersonalIDRejectsOutOfRange(t *testing.T) {
	var pokemon Pokemon
	if err := Decode(json.RawMessage(`{"personal_id":4294967296}`), &pokemon); err == nil {
		t.Fatal("overflowing personal_id accepted")
	}
	if err := Decode(json.RawMessage(`{"personal_id":-1}`), &pokemon); err == nil {
		t.Fatal("negative personal_id accepted")
	}
}

func TestDuelPartyValidateLength(t *testing.T) {
	rules := DuelRules{PartySize: 2, HeldItems: true, TurnSeconds: 60}
	if (DuelParty{Party: []Pokemon{validPokemon()}}).Validate(rules) == nil {
		t.Fatal("short party accepted")
	}
	if err := (DuelParty{Party: []Pokemon{validPokemon(), validPokemon()}}).Validate(rules); err != nil {
		t.Fatalf("party rejected: %v", err)
	}
}

func TestDuelActionValidate(t *testing.T) {
	rules := DuelRules{PartySize: 3, TurnSeconds: 60}
	cases := []struct {
		action DuelAction
		valid  bool
	}{
		{DuelAction{ActionMove, 3}, true},
		{DuelAction{ActionMove, 4}, false},
		{DuelAction{ActionMove, -1}, false},
		{DuelAction{ActionSwitch, 2}, true},
		{DuelAction{ActionSwitch, 3}, false},
		{DuelAction{"run", 0}, false},
	}
	for _, tc := range cases {
		if err := tc.action.Validate(rules); (err == nil) != tc.valid {
			t.Errorf("%+v: %v", tc.action, err)
		}
	}
}

func TestDuelHashAndResultValidate(t *testing.T) {
	if err := (DuelHash{Round: 1, Hash: strings.Repeat("a", 64)}).Validate(); err != nil {
		t.Fatalf("hash rejected: %v", err)
	}
	for _, hash := range []DuelHash{{Round: 1, Hash: strings.Repeat("a", 65)}, {Round: 1}, {Hash: "a"}} {
		if hash.Validate() == nil {
			t.Errorf("%+v accepted", hash)
		}
	}
	if (DuelResult{Winner: number(2)}).Validate() == nil {
		t.Error("winner 2 accepted")
	}
	if err := (DuelResult{}).Validate(); err != nil {
		t.Errorf("null winner rejected: %v", err)
	}
}

// maximalPokemon fills every field to its largest encoded size. '<' is the
// costliest name character: encoding/json writes it as a six-byte escape.
func maximalPokemon() Pokemon {
	symbol := strings.Repeat("A", 32)
	sprite := strings.Repeat("a", 64)
	moves := make([]PokemonMove, maxMoves)
	for i := range moves {
		moves[i] = PokemonMove{ID: symbol, PP: 255, PPUp: 3}
	}
	return Pokemon{
		Species: symbol, Level: 100, Form: 99, PersonalID: 4294967295, Gender: 2,
		Nature: symbol, Ability: &symbol, AbilityIndex: number(5), Item: &symbol,
		Happiness: 255, IV: []int{31, 31, 31, 31, 31, 31},
		IVMaxed: []bool{false, false, false, false, false, false},
		EV:      []int{252, 252, 6, 0, 0, 0}, Moves: moves,
		Name: strings.Repeat("<", maxPokemonNameRune), Shiny: false, HeadShiny: false, BodyShiny: false,
		HiddenPowerType: &symbol, SizeCategory: &symbol, PifSprite: &sprite,
	}
}

func TestMaximalPartiesFitInAFrame(t *testing.T) {
	party := make([]Pokemon, maxPartySize)
	for i := range party {
		party[i] = maximalPokemon()
	}
	rules := DuelRules{PartySize: 6, HeldItems: true, TurnSeconds: 60}
	asset := strings.Repeat("a", 64)
	appearance := Appearance{Skin: maxSkin, Clothes: &asset, Hair: &asset, Hat: &asset, Hat2: &asset,
		ClothesColor: -maxColorShift, HairColor: -maxColorShift, HatColor: -maxColorShift, Hat2Color: -maxColorShift}
	if err := (DuelParty{Party: party, Appearance: appearance}).Validate(rules); err != nil {
		t.Fatal(err)
	}
	name := strings.Repeat("<", maxNameRunes)
	frames := map[string]interface{}{
		TypeDuelParty: DuelParty{Party: party, Appearance: appearance},
		TypeDuelStart: DuelStart{
			Seed: 4294967295, Side: 1, Rules: rules,
			Players: [2]DuelPlayer{
				{ID: 4294967295, Name: name, Appearance: appearance},
				{ID: 4294967295, Name: name, Appearance: appearance},
			},
			Parties: [2][]Pokemon{party, party},
		},
	}
	for msgType, payload := range frames {
		frame, err := Encode(msgType, payload)
		if err != nil {
			t.Fatal(err)
		}
		if len(frame) > MaxFrameBytes {
			t.Errorf("%s frame is %d bytes, limit %d", msgType, len(frame), MaxFrameBytes)
		}
		t.Logf("%s: %d bytes", msgType, len(frame))
	}
}

func TestDuelRulesClauses(t *testing.T) {
	cases := []struct {
		name    string
		clauses []string
		valid   bool
	}{
		{"accepts none", nil, true},
		{"accepts known", []string{"sleep", "species"}, true},
		{"rejects unknown", []string{"nope"}, false},
		{"rejects duplicates", []string{"sleep", "sleep"}, false},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			rules := DuelRules{PartySize: 1, TurnSeconds: 60, Clauses: tc.clauses}
			if err := rules.Validate(); (err == nil) != tc.valid {
				t.Fatalf("Validate() = %v", err)
			}
		})
	}
}

func TestPartyClauses(t *testing.T) {
	member := func(species string, item *string) Pokemon {
		pokemon := validPokemon()
		pokemon.Species = species
		pokemon.Item = item
		return pokemon
	}
	cases := []struct {
		name   string
		clause string
		party  []Pokemon
		valid  bool
	}{
		{"species accepts distinct", "species", []Pokemon{member("B1H2", nil), member("B2H1", nil)}, true},
		{"species rejects same head and body", "species", []Pokemon{member("B1H2", nil), member("B1H2", nil)}, false},
		{"item accepts several without item", "item", []Pokemon{member("A", nil), member("B", nil)}, true},
		{"item rejects duplicate", "item", []Pokemon{member("A", text("LEFTOVERS")), member("B", text("LEFTOVERS"))}, false},
		{"no_fusion accepts plain", "no_fusion", []Pokemon{member("PIKACHU", nil), member("MEW", nil)}, true},
		{"no_fusion rejects fusion", "no_fusion", []Pokemon{member("PIKACHU", nil), member("B1H2", nil)}, false},
		{"client-checked clause passes the server", "no_legendary", []Pokemon{member("MEWTWO", nil), member("MEW", nil)}, true},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			rules := DuelRules{PartySize: 2, HeldItems: true, TurnSeconds: 60, Clauses: []string{tc.clause}}
			if err := (DuelParty{Party: tc.party}).Validate(rules); (err == nil) != tc.valid {
				t.Fatalf("Validate() = %v", err)
			}
		})
	}
}
