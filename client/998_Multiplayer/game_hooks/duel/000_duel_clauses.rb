module Multiplayer
  # The optional rules of a duel. Adding one is one entry in ALL here (and one
  # in duelClauses on the server, which must know its id).
  module DuelClauses
    # engine_rule is the key the engine's clauses read from battle.rules, or
    # nil. broken_by takes the decoded party and tells whether it is illegal.
    Clause = Struct.new(:id, :label, :engine_rule, :broken_by)

    def self.repeats?(values)
      values.uniq.size != values.size
    end

    def self.triple_fusion?(pokemon)
      pokemon.isTripleFusion?
    end

    def self.legendary?(pokemon)
      triple_fusion?(pokemon) || is_fusion_of_any(pokemon.species, LEGENDARIES_LIST)
    end

    def self.fusion?(pokemon)
      pokemon.isFusion? || triple_fusion?(pokemon)
    end

    ALL = [
      Clause.new("sleep", "Sleep Clause", "sleepclause", nil),
      Clause.new("freeze", "Freeze Clause", "freezeclause", nil),
      Clause.new("ohko", "OHKO Clause", "ohkoclause", nil),
      Clause.new("evasion", "Evasion Clause", "evasionclause", nil),
      Clause.new("perish", "Perish Clause", "perishsongclause", nil),
      Clause.new("skill_swap", "Skill Swap Clause", "skillswapclause", nil),
      Clause.new("sonic_boom", "Fixed Damage Clause", "sonicboomclause", nil),
      Clause.new("species", "Species Clause", nil, ->(party) { repeats?(party.map(&:species)) }),
      Clause.new("item", "Item Clause", nil, ->(party) { repeats?(party.map(&:item_id).compact) }),
      Clause.new("moody", "No Moody", nil, ->(party) { party.any? { |pokemon| pokemon.ability_id == :MOODY } }),
      Clause.new("no_legendary", "No legendaries", nil, ->(party) { party.any? { |pokemon| legendary?(pokemon) } }),
      Clause.new("no_fusion", "No fusions", nil, ->(party) { party.any? { |pokemon| fusion?(pokemon) } })
    ].freeze
    UNREADABLE_TEAM = Clause.new(nil, "Valid team data", nil, nil).freeze
    # The server only accepts ids it knows, so unknown ones cannot reach here
    # from a compatible server: they are skipped rather than trusted.
    BY_ID = ALL.to_h { |clause| [clause.id, clause] }.freeze

    def self.named(ids)
      Array(ids).map { |id| BY_ID[id] }.compact
    end

    # Returns the first clause a wire party breaks, or nil if it is legal.
    def self.violation(wire_party, ids)
      party = PartyCodec.decode(wire_party)
      named(ids).find { |clause| clause.broken_by&.call(party) }
    rescue PartyCodec::InvalidParty
      UNREADABLE_TEAM
    end

    def self.apply_to(battle, ids)
      named(ids).each { |clause| battle.rules[clause.engine_rule] = true if clause.engine_rule }
    end
  end
end
