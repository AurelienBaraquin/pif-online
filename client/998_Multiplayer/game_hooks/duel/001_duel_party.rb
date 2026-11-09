module Multiplayer
  # Builds the party the local player brings to a duel.
  module DuelParty
    def self.available_count
      $Trainer.able_party.size
    end

    # Returns nil when the team cannot play under the rules any more: it may
    # have changed since the challenge, and the server refuses illegal parties.
    def self.for_rules(rules)
      party = adjusted_party(rules)
      party.size == rules.party_size && !DuelClauses.violation(party, rules.clauses) ? party : nil
    end

    # Returns the clause the local team breaks under these rules, or nil.
    def self.violation(rules)
      DuelClauses.violation(adjusted_party(rules), rules.clauses)
    end

    def self.adjusted_party(rules)
      PartyCodec.encode($Trainer.able_party.first(rules.party_size)).map { |pokemon| apply_rules(pokemon, rules) }
    end

    def self.appearance
      LocalPlayer.appearance
    end

    def self.apply_rules(pokemon, rules)
      adjusted = pokemon.dup
      adjusted["level"] = rules.level if rules.level.positive?
      adjusted["item"] = nil unless rules.held_items
      adjusted
    end
  end

  Runtime.register_feature(Duel::FEATURE_NAME) { |client| Duel.new(client, DuelParty) }
end
