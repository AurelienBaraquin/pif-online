package duel_test

import (
	"reflect"
	"strings"
	"testing"
	"time"

	"github.com/AurelienBaraquin/pif-online/server/internal/protocol"
)

const (
	turn         = 60 * time.Second
	resolving    = turn + 60*time.Second
	challengeTTL = 30 * time.Second
	grace        = 15 * time.Second
)

func TestChallengeAcceptedStartsDuelWithSharedView(t *testing.T) {
	server := startServer(t)
	alice, bob := join(t, server, "Alice"), join(t, server, "Bob")

	alice.send(protocol.TypeDuelChallenge, protocol.DuelChallenge{Target: bob.id, Rules: testRules})
	var invited protocol.DuelInvited
	bob.expect(protocol.TypeDuelInvited, &invited)
	if !reflect.DeepEqual(invited, protocol.DuelInvited{From: alice.id, Name: "Alice", Rules: testRules}) {
		t.Fatalf("invited = %+v", invited)
	}
	bob.send(protocol.TypeDuelResponse, protocol.DuelResponse{From: alice.id, Accept: true})
	var acceptedA, acceptedB protocol.DuelAccepted
	alice.expect(protocol.TypeDuelAccepted, &acceptedA)
	bob.expect(protocol.TypeDuelAccepted, &acceptedB)
	if acceptedA.Opponent != bob.id || acceptedB.Opponent != alice.id {
		t.Fatalf("accepted = %+v %+v", acceptedA, acceptedB)
	}

	aliceParty := testParty()
	clothes := "basic"
	aliceParty.Appearance = protocol.Appearance{Skin: 3, Clothes: &clothes, ClothesColor: 120}
	alice.send(protocol.TypeDuelParty, aliceParty)
	alice.sync()
	bob.send(protocol.TypeDuelParty, testParty())

	var startA, startB protocol.DuelStart
	alice.expect(protocol.TypeDuelStart, &startA)
	bob.expect(protocol.TypeDuelStart, &startB)
	if startA.Side != 0 || startB.Side != 1 {
		t.Fatalf("sides = %d, %d", startA.Side, startB.Side)
	}
	startB.Side = 0
	if !reflect.DeepEqual(startA, startB) {
		t.Fatalf("views differ: %+v / %+v", startA, startB)
	}
	if startA.Players[0].ID != alice.id || startA.Players[1].Name != "Bob" || startA.Parties[1][0].Species != "PIKACHU" {
		t.Fatalf("start = %+v", startA)
	}
	if !reflect.DeepEqual(startA.Players[0].Appearance, aliceParty.Appearance) {
		t.Fatalf("appearance = %+v", startA.Players[0].Appearance)
	}
}

func TestPartiesOmitUnknownFields(t *testing.T) {
	server := startServer(t)
	alice, bob := join(t, server, "Alice"), join(t, server, "Bob")
	accept(alice, bob)

	frame, err := protocol.Encode(protocol.TypeDuelParty, testParty())
	if err != nil {
		t.Fatal(err)
	}
	withExtra := strings.Replace(string(frame), `"species":`, `"evil":"x","species":`, 1)
	alice.raw(withExtra)
	bob.send(protocol.TypeDuelParty, testParty())

	var start map[string]interface{}
	bob.expect(protocol.TypeDuelStart, &start)
	parties := start["parties"].([]interface{})
	first := parties[0].([]interface{})[0].(map[string]interface{})
	if _, leaked := first["evil"]; leaked {
		t.Fatal("unknown field forwarded")
	}
}

func TestDeclines(t *testing.T) {
	server := startServer(t)
	alice, bob, carol := join(t, server, "Alice"), join(t, server, "Bob"), join(t, server, "Carol")

	alice.send(protocol.TypeDuelChallenge, protocol.DuelChallenge{Target: 9999, Rules: testRules})
	alice.expectDeclined(9999, protocol.DeclineOffline)

	challenge(alice, bob)
	carol.send(protocol.TypeDuelChallenge, protocol.DuelChallenge{Target: bob.id, Rules: testRules})
	carol.expectDeclined(bob.id, protocol.DeclineBusy)
	carol.send(protocol.TypeDuelChallenge, protocol.DuelChallenge{Target: alice.id, Rules: testRules})
	carol.expectDeclined(alice.id, protocol.DeclineBusy)
	alice.send(protocol.TypeDuelChallenge, protocol.DuelChallenge{Target: carol.id, Rules: testRules})
	alice.expectDeclined(carol.id, protocol.DeclineBusy)

	bob.send(protocol.TypeDuelResponse, protocol.DuelResponse{From: alice.id, Accept: false})
	alice.expectDeclined(bob.id, protocol.DeclineRefused)

	challenge(alice, carol)
}

func TestChallengeExpiresOnTickAndLateResponseIsHarmless(t *testing.T) {
	server := startServer(t)
	alice, bob := join(t, server, "Alice"), join(t, server, "Bob")
	challenge(alice, bob)

	server.clock.advance(challengeTTL - time.Second)
	bob.sync()
	alice.sync()
	server.clock.advance(time.Second)

	alice.expectDeclined(bob.id, protocol.DeclineExpired)
	bob.expectDeclined(alice.id, protocol.DeclineExpired)

	bob.send(protocol.TypeDuelResponse, protocol.DuelResponse{From: alice.id, Accept: true})
	bob.sync()
	alice.sync()
}

func TestPartiesExpire(t *testing.T) {
	server := startServer(t)
	alice, bob := join(t, server, "Alice"), join(t, server, "Bob")
	accept(alice, bob)

	alice.send(protocol.TypeDuelParty, testParty())
	alice.sync()
	server.clock.advance(challengeTTL)

	alice.expectDeclined(bob.id, protocol.DeclineExpired)
	bob.expectDeclined(alice.id, protocol.DeclineExpired)
}

func TestDisconnectBeforeBattleTellsTheOtherPlayer(t *testing.T) {
	server := startServer(t)
	alice, bob := join(t, server, "Alice"), join(t, server, "Bob")
	challenge(alice, bob)

	alice.conn.Close()

	bob.expectDeclined(alice.id, protocol.DeclineOffline)
}

func TestTurnIsRevealedOnlyOnceBothChose(t *testing.T) {
	server := startServer(t)
	alice, bob := join(t, server, "Alice"), join(t, server, "Bob")
	begin(alice, bob)

	alice.send(protocol.TypeDuelChoice, protocol.DuelChoice{
		Round: 1, DuelAction: protocol.DuelAction{Action: protocol.ActionMove, Index: 2},
	})
	alice.sync()
	bob.sync()
	bob.send(protocol.TypeDuelChoice, protocol.DuelChoice{
		Round: 1, DuelAction: protocol.DuelAction{Action: protocol.ActionSwitch, Index: 0},
	})

	var turnA, turnB protocol.DuelTurn
	alice.expect(protocol.TypeDuelTurn, &turnA)
	bob.expect(protocol.TypeDuelTurn, &turnB)
	want := protocol.DuelTurn{Round: 1, Choices: [2]protocol.DuelAction{
		{Action: protocol.ActionMove, Index: 2},
		{Action: protocol.ActionSwitch, Index: 0},
	}}
	if turnA != want || turnB != want {
		t.Fatalf("turns = %+v / %+v", turnA, turnB)
	}
	playRound(alice, bob, 2)
}

func TestTimeouts(t *testing.T) {
	cases := []struct {
		name   string
		act    func(alice, bob *testClient)
		winner *int
	}{
		{"bob silent", func(alice, bob *testClient) { choose(alice, 1); alice.sync() }, side(0)},
		{"alice silent", func(alice, bob *testClient) { choose(bob, 1); bob.sync() }, side(1)},
		{"both silent", func(alice, bob *testClient) {}, nil},
		{"reported result counts as acted", func(alice, bob *testClient) {
			alice.send(protocol.TypeDuelResult, protocol.DuelResult{Winner: side(0)})
			alice.sync()
		}, side(0)},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			server := startServer(t)
			alice, bob := join(t, server, "Alice"), join(t, server, "Bob")
			begin(alice, bob)
			tc.act(alice, bob)

			server.clock.advance(turn)

			alice.expectEnded(protocol.EndTimeout, tc.winner)
			bob.expectEnded(protocol.EndTimeout, tc.winner)
		})
	}
}

func TestNewRoundRestartsTimer(t *testing.T) {
	server := startServer(t)
	alice, bob := join(t, server, "Alice"), join(t, server, "Bob")
	begin(alice, bob)
	server.clock.advance(turn - time.Second)
	playRound(alice, bob, 1)

	server.clock.advance(resolving - time.Second)
	alice.sync()
	bob.sync()

	server.clock.advance(time.Second)
	alice.expectEnded(protocol.EndTimeout, nil)
}

func TestReplacementIsForwardedAndRestartsTimer(t *testing.T) {
	server := startServer(t)
	alice, bob := join(t, server, "Alice"), join(t, server, "Bob")
	begin(alice, bob)
	playRound(alice, bob, 1)
	server.clock.advance(turn - time.Second)

	bob.send(protocol.TypeDuelReplacement, protocol.DuelReplacement{Seq: 0, Index: 0})

	want := protocol.DuelReplaced{Side: 1, Seq: 0, Index: 0}
	var gotA, gotB protocol.DuelReplaced
	alice.expect(protocol.TypeDuelReplaced, &gotA)
	bob.expect(protocol.TypeDuelReplaced, &gotB)
	if gotA != want || gotB != want {
		t.Fatalf("replaced = %+v / %+v", gotA, gotB)
	}
	server.clock.advance(resolving - time.Second)
	alice.sync()
	bob.sync()
	server.clock.advance(time.Second)
	alice.expectEnded(protocol.EndTimeout, nil)
}

func TestStalledReplacementLosesOnlyAfterAdmission(t *testing.T) {
	admit := func(c *testClient) { c.send(protocol.TypeDuelReplacing, nil) }
	replace := func(c *testClient) {
		c.send(protocol.TypeDuelReplacement, protocol.DuelReplacement{Seq: 0, Index: 0})
	}
	cases := []struct {
		name     string
		act      func(alice, bob *testClient)
		replaced bool
		winner   *int
	}{
		{"nobody admits", func(_, _ *testClient) {}, false, nil},
		{"alice owes", func(alice, _ *testClient) { admit(alice) }, false, side(1)},
		{"bob owes", func(_, bob *testClient) { admit(bob) }, false, side(0)},
		{"both owe", func(alice, bob *testClient) { admit(alice); admit(bob) }, false, nil},
		{"alice owed and replaced", func(alice, _ *testClient) { admit(alice); replace(alice) }, true, nil},
		{"both owed, alice replaced", func(alice, bob *testClient) { admit(alice); admit(bob); replace(alice) }, true, side(0)},
	}
	for _, tc := range cases {
		tc := tc
		t.Run(tc.name, func(t *testing.T) {
			server := startServer(t)
			alice, bob := join(t, server, "Alice"), join(t, server, "Bob")
			begin(alice, bob)
			playRound(alice, bob, 1)
			tc.act(alice, bob)
			clients := []*testClient{alice, bob}
			for _, client := range clients {
				if tc.replaced {
					client.expect(protocol.TypeDuelReplaced, nil)
				}
				client.sync()
			}

			server.clock.advance(resolving)

			for _, client := range clients {
				client.expectEnded(protocol.EndTimeout, tc.winner)
			}
		})
	}
}

func TestAdmissionIsClearedByANewRound(t *testing.T) {
	server := startServer(t)
	alice, bob := join(t, server, "Alice"), join(t, server, "Bob")
	begin(alice, bob)
	playRound(alice, bob, 1)
	alice.send(protocol.TypeDuelReplacing, nil)
	alice.sync()
	playRound(alice, bob, 2)

	server.clock.advance(resolving)

	alice.expectEnded(protocol.EndTimeout, nil)
	bob.expectEnded(protocol.EndTimeout, nil)
}

func TestReplacingBeforeFirstRoundIsRejected(t *testing.T) {
	server := startServer(t)
	alice, bob := join(t, server, "Alice"), join(t, server, "Bob")
	begin(alice, bob)
	alice.send(protocol.TypeDuelReplacing, nil)
	alice.expectKicked()
}

func TestHashesCompareOncePerRound(t *testing.T) {
	server := startServer(t)
	alice, bob := join(t, server, "Alice"), join(t, server, "Bob")
	begin(alice, bob)
	playRound(alice, bob, 1)
	playRound(alice, bob, 2)

	alice.send(protocol.TypeDuelHash, protocol.DuelHash{Round: 1, Hash: "same"})
	alice.send(protocol.TypeDuelHash, protocol.DuelHash{Round: 2, Hash: "left"})
	bob.send(protocol.TypeDuelHash, protocol.DuelHash{Round: 1, Hash: "same"})
	bob.sync()
	alice.sync()

	bob.send(protocol.TypeDuelHash, protocol.DuelHash{Round: 2, Hash: "right"})

	alice.expectEnded(protocol.EndDesync, nil)
	bob.expectEnded(protocol.EndDesync, nil)
}

func TestResultsMustAgree(t *testing.T) {
	cases := []struct {
		name   string
		a, b   *int
		reason string
		winner *int
	}{
		{"agree on a winner", side(1), side(1), protocol.EndFinished, side(1)},
		{"agree on a draw", nil, nil, protocol.EndFinished, nil},
		{"disagree", side(0), side(1), protocol.EndDesync, nil},
		{"draw against winner", nil, side(1), protocol.EndDesync, nil},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			server := startServer(t)
			alice, bob := join(t, server, "Alice"), join(t, server, "Bob")
			begin(alice, bob)

			alice.send(protocol.TypeDuelResult, protocol.DuelResult{Winner: tc.a})
			alice.sync()
			bob.send(protocol.TypeDuelResult, protocol.DuelResult{Winner: tc.b})

			alice.expectEnded(tc.reason, tc.winner)
			bob.expectEnded(tc.reason, tc.winner)
		})
	}
}

func TestForfeitAndDisconnectEndDuel(t *testing.T) {
	server := startServer(t)
	alice, bob := join(t, server, "Alice"), join(t, server, "Bob")
	begin(alice, bob)

	alice.send(protocol.TypeDuelForfeit, nil)
	alice.expectEnded(protocol.EndForfeit, side(1))
	bob.expectEnded(protocol.EndForfeit, side(1))

	begin(alice, bob)
	bob.conn.Close()
	alice.expectEnded(protocol.EndDisconnect, side(0))
}

func TestInFlightMessagesAfterDuelAreIgnoredThenRejected(t *testing.T) {
	server := startServer(t)
	alice, bob := join(t, server, "Alice"), join(t, server, "Bob")
	begin(alice, bob)
	alice.send(protocol.TypeDuelForfeit, nil)
	alice.expectEnded(protocol.EndForfeit, side(1))
	bob.expectEnded(protocol.EndForfeit, side(1))

	choose(bob, 1)
	bob.sync()

	server.clock.advance(grace)
	choose(bob, 1)
	bob.expectKicked()
}

func TestMessagesOutsideADuelDisconnect(t *testing.T) {
	cases := []struct {
		name string
		line string
	}{
		{"party", `{"t":"duel_party","d":{"party":[]}}`},
		{"choice", `{"t":"duel_choice","d":{"round":1,"action":"move","index":0}}`},
		{"replacement", `{"t":"duel_replacement","d":{"seq":0,"index":0}}`},
		{"hash", `{"t":"duel_hash","d":{"round":1,"hash":"x"}}`},
		{"result", `{"t":"duel_result","d":{"winner":0}}`},
		{"forfeit", `{"t":"duel_forfeit"}`},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			server := startServer(t)
			witness, attacker := join(t, server, "Witness"), join(t, server, "Attacker")

			attacker.raw(tc.line)

			attacker.expectKicked()
			witness.sync()
		})
	}
}

func TestInvalidDuelMessagesEndTheSendersDuelOnly(t *testing.T) {
	cases := []struct {
		name    string
		prepare func(alice, bob *testClient)
		line    string
	}{
		{"second choice", func(a, b *testClient) { choose(a, 1); a.sync() }, `{"t":"duel_choice","d":{"round":1,"action":"move","index":0}}`},
		{"future round", nil, `{"t":"duel_choice","d":{"round":2,"action":"move","index":0}}`},
		{"past round", func(a, b *testClient) { playRound(a, b, 1) }, `{"t":"duel_choice","d":{"round":1,"action":"move","index":0}}`},
		{"unknown action", nil, `{"t":"duel_choice","d":{"round":1,"action":"run","index":0}}`},
		{"switch beyond party", nil, `{"t":"duel_choice","d":{"round":1,"action":"switch","index":1}}`},
		{"replacement in round 1", nil, `{"t":"duel_replacement","d":{"seq":0,"index":0}}`},
		{"replacement beyond party", func(a, b *testClient) { playRound(a, b, 1) }, `{"t":"duel_replacement","d":{"seq":0,"index":1}}`},
		{"replayed replacement", func(a, b *testClient) {
			playRound(a, b, 1)
			a.send(protocol.TypeDuelReplacement, protocol.DuelReplacement{Seq: 3, Index: 0})
			a.expect(protocol.TypeDuelReplaced, nil)
			b.expect(protocol.TypeDuelReplaced, nil)
		}, `{"t":"duel_replacement","d":{"seq":3,"index":0}}`},
		{"hash for unresolved round", nil, `{"t":"duel_hash","d":{"round":1,"hash":"x"}}`},
		{"hash out of order", func(a, b *testClient) { playRound(a, b, 1); playRound(a, b, 2) }, `{"t":"duel_hash","d":{"round":2,"hash":"x"}}`},
		{"second hash", func(a, b *testClient) {
			playRound(a, b, 1)
			a.send(protocol.TypeDuelHash, protocol.DuelHash{Round: 1, Hash: "x"})
			a.sync()
		}, `{"t":"duel_hash","d":{"round":1,"hash":"x"}}`},
		{"oversized hash", func(a, b *testClient) { playRound(a, b, 1) }, `{"t":"duel_hash","d":{"round":1,"hash":"` + strings.Repeat("a", 65) + `"}}`},
		{"second result", func(a, b *testClient) {
			a.send(protocol.TypeDuelResult, protocol.DuelResult{})
			a.sync()
		}, `{"t":"duel_result","d":{"winner":null}}`},
		{"invalid winner", nil, `{"t":"duel_result","d":{"winner":2}}`},
		{"wrong payload type", nil, `{"t":"duel_choice","d":"x"}`},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			server := startServer(t)
			alice, bob := join(t, server, "Alice"), join(t, server, "Bob")
			carol, dave := join(t, server, "Carol"), join(t, server, "Dave")
			begin(alice, bob)
			begin(carol, dave)
			if tc.prepare != nil {
				tc.prepare(alice, bob)
			}

			alice.raw(tc.line)

			alice.expectKicked()
			bob.expectEnded(protocol.EndDisconnect, side(1))
			playRound(carol, dave, 1)
		})
	}
}

func TestInvalidChallengesAndPartiesDisconnect(t *testing.T) {
	cases := []struct {
		name string
		line string
	}{
		{"bad rules", `{"t":"duel_challenge","d":{"target":1,"rules":{"party_size":0,"turn_seconds":60}}}`},
		{"null rules", `{"t":"duel_challenge","d":{"target":1}}`},
		{"no payload", `{"t":"duel_challenge"}`},
		{"bad response payload", `{"t":"duel_response","d":[]}`},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			server := startServer(t)
			witness, attacker := join(t, server, "Witness"), join(t, server, "Attacker")

			attacker.raw(tc.line)

			attacker.expectKicked()
			witness.sync()
		})
	}
}

func TestChallengingOneselfDisconnects(t *testing.T) {
	server := startServer(t)
	alice := join(t, server, "Alice")

	alice.send(protocol.TypeDuelChallenge, protocol.DuelChallenge{Target: alice.id, Rules: testRules})

	alice.expectKicked()
}

func TestInvalidPartyDisconnectsSenderOnly(t *testing.T) {
	cases := []struct {
		name  string
		party func() protocol.DuelParty
	}{
		{"wrong size", func() protocol.DuelParty { return protocol.DuelParty{} }},
		{"traversal sprite", func() protocol.DuelParty {
			party := testParty()
			sprite := "a..b"
			party.Party[0].PifSprite = &sprite
			return party
		}},
		{"traversal appearance", func() protocol.DuelParty {
			party := testParty()
			clothes := "a..b"
			party.Appearance.Clothes = &clothes
			return party
		}},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			server := startServer(t)
			alice, bob := join(t, server, "Alice"), join(t, server, "Bob")
			accept(alice, bob)

			alice.send(protocol.TypeDuelParty, tc.party())

			alice.expectKicked()
			bob.expectDeclined(alice.id, protocol.DeclineOffline)
		})
	}
}

func TestSecondPartyDisconnects(t *testing.T) {
	server := startServer(t)
	alice, bob := join(t, server, "Alice"), join(t, server, "Bob")
	accept(alice, bob)
	alice.send(protocol.TypeDuelParty, testParty())
	alice.sync()

	alice.send(protocol.TypeDuelParty, testParty())

	alice.expectKicked()
}

func TestTimeoutInOneDuelDoesNotAffectAnother(t *testing.T) {
	server := startServer(t)
	alice, bob := join(t, server, "Alice"), join(t, server, "Bob")
	carol, dave := join(t, server, "Carol"), join(t, server, "Dave")
	begin(alice, bob)
	server.clock.advance(turn - time.Second)
	begin(carol, dave)

	server.clock.advance(time.Second)

	alice.expectEnded(protocol.EndTimeout, nil)
	bob.expectEnded(protocol.EndTimeout, nil)
	playRound(carol, dave, 1)
}

func TestTimerStartsOnceBothFinishedTheRound(t *testing.T) {
	server := startServer(t)
	alice, bob := join(t, server, "Alice"), join(t, server, "Bob")
	begin(alice, bob)
	playRound(alice, bob, 1)
	server.clock.advance(resolving - time.Second)
	alice.sync()

	for _, client := range []*testClient{alice, bob} {
		client.send(protocol.TypeDuelHash, protocol.DuelHash{Round: 1, Hash: "same"})
		client.sync()
	}
	server.clock.advance(turn - time.Second)
	alice.sync()
	bob.sync()

	server.clock.advance(time.Second)
	alice.expectEnded(protocol.EndTimeout, nil)
	bob.expectEnded(protocol.EndTimeout, nil)
}

func TestSlowAnimationDoesNotTimeOut(t *testing.T) {
	server := startServer(t)
	alice, bob := join(t, server, "Alice"), join(t, server, "Bob")
	begin(alice, bob)
	playRound(alice, bob, 1)

	server.clock.advance(turn)

	alice.sync()
	bob.sync()
}

func TestRejectEndsDuelWithoutWinner(t *testing.T) {
	server := startServer(t)
	alice, bob := join(t, server, "Alice"), join(t, server, "Bob")
	begin(alice, bob)

	bob.send(protocol.TypeDuelReject, nil)

	alice.expectEnded(protocol.EndIllegal, nil)
	bob.expectEnded(protocol.EndIllegal, nil)
}

func TestRejectWhileSendingParties(t *testing.T) {
	server := startServer(t)
	alice, bob := join(t, server, "Alice"), join(t, server, "Bob")
	accept(alice, bob)

	alice.send(protocol.TypeDuelReject, nil)

	alice.expectEnded(protocol.EndIllegal, nil)
	bob.expectEnded(protocol.EndIllegal, nil)
}

func TestRejectAfterFirstRoundDisconnects(t *testing.T) {
	server := startServer(t)
	alice, bob := join(t, server, "Alice"), join(t, server, "Bob")
	begin(alice, bob)
	playRound(alice, bob, 1)

	alice.send(protocol.TypeDuelReject, nil)

	alice.expectKicked()
}
