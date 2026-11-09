package protocol

import "regexp"

// fusionSpeciesPattern matches the species id of a two-Pokémon fusion.
var fusionSpeciesPattern = regexp.MustCompile(`^B[1-9][0-9]*H[1-9][0-9]*$`)

// partyCheck rejects a party that breaks a clause.
type partyCheck func(party []Pokemon) error

// duelClauses holds every clause a challenge may name; adding one is one entry.
// A nil check means the party payload cannot prove a violation: the clause
// either only changes the simulation or needs game data held by the clients.
var duelClauses = map[string]partyCheck{
	"sleep":        nil,
	"freeze":       nil,
	"ohko":         nil,
	"evasion":      nil,
	"perish":       nil,
	"skill_swap":   nil,
	"sonic_boom":   nil,
	"moody":        nil,
	"no_legendary": nil,
	"species":      uniqueSpecies,
	"item":         uniqueItems,
	"no_fusion":    noFusions,
}

func uniqueSpecies(party []Pokemon) error {
	seen := make(map[string]bool, len(party))
	for _, pokemon := range party {
		if seen[pokemon.Species] {
			return invalid("species clause")
		}
		seen[pokemon.Species] = true
	}
	return nil
}

func uniqueItems(party []Pokemon) error {
	seen := make(map[string]bool, len(party))
	for _, pokemon := range party {
		if pokemon.Item == nil {
			continue
		}
		if seen[*pokemon.Item] {
			return invalid("item clause")
		}
		seen[*pokemon.Item] = true
	}
	return nil
}

func noFusions(party []Pokemon) error {
	for _, pokemon := range party {
		if fusionSpeciesPattern.MatchString(pokemon.Species) {
			return invalid("fusion banned")
		}
	}
	return nil
}

func (r DuelRules) validateClauses() error {
	named := make(map[string]bool, len(r.Clauses))
	for _, clause := range r.Clauses {
		if _, known := duelClauses[clause]; !known || named[clause] {
			return invalid("clause")
		}
		named[clause] = true
	}
	return nil
}

func (r DuelRules) checkClauses(party []Pokemon) error {
	for _, clause := range r.Clauses {
		if check := duelClauses[clause]; check != nil {
			if err := check(party); err != nil {
				return err
			}
		}
	}
	return nil
}
