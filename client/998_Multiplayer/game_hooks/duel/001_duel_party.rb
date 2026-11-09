module Multiplayer
  # Builds the party the local player brings to a duel.
  module DuelParty
    def self.available_count
      $Trainer.able_party.size
    end

    def self.for_rules(rules)
      party = $Trainer.able_party.first(rules.party_size)
      PartyCodec.encode(party).map { |pokemon| apply_rules(pokemon, rules) }
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
