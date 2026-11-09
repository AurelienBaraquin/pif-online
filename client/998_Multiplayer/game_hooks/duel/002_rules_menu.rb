module Multiplayer
  # Lets the player set the rules of a duel before sending the challenge.
  module RulesMenu
    LEVELS = [0, 5, 50, 100].freeze
    TURN_SECONDS = [30, 60, 90, 120, 300].freeze
    DEFAULT_PARTY_SIZE = 3
    DEFAULT_TURN_SECONDS = 60
    SEND_INDEX = 4
    CANCEL_INDEX = 5

    # Returns the chosen Duel::Rules, or nil if the player backs out.
    def self.choose(max_party_size)
      rules = Duel::Rules.new([DEFAULT_PARTY_SIZE, max_party_size].min, 0, true, DEFAULT_TURN_SECONDS)
      cursor = SEND_INDEX
      loop do
        cursor = pbMessage(_INTL("Set the rules of the duel."), commands(rules), CANCEL_INDEX, nil, cursor)
        return rules if cursor == SEND_INDEX
        return nil if cursor == CANCEL_INDEX
        rules = changed(rules, cursor, max_party_size)
      end
    end

    def self.commands(rules)
      [_INTL("Team size: {1}", rules.party_size), _INTL("Level: {1}", level_label(rules.level)),
       _INTL("Held items: {1}", rules.held_items ? _INTL("Allowed") : _INTL("Banned")),
       _INTL("Turn timer: {1}s", rules.turn_seconds), _INTL("Send challenge"), _INTL("Cancel")]
    end

    def self.level_label(level)
      level.positive? ? level.to_s : _INTL("Unchanged")
    end

    def self.summary(rules)
      _INTL("Team of {1}, level {2}, held items {3}, {4}s per turn.", rules.party_size,
            level_label(rules.level), rules.held_items ? _INTL("allowed") : _INTL("banned"), rules.turn_seconds)
    end

    def self.changed(rules, index, max_party_size)
      updated = rules.dup
      case index
      when 0 then updated.party_size = rules.party_size % max_party_size + 1
      when 1 then updated.level = next_value(LEVELS, rules.level)
      when 2 then updated.held_items = !rules.held_items
      when 3 then updated.turn_seconds = next_value(TURN_SECONDS, rules.turn_seconds)
      end
      updated
    end

    def self.next_value(values, current)
      values[(values.index(current) + 1) % values.size]
    end
  end
end
