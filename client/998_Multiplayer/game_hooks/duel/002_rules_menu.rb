module Multiplayer
  # Lets the player set the rules of a duel before sending the challenge. The
  # clauses live on their own pages because a command window has few lines.
  module RulesMenu
    LEVELS = [0, 5, 50, 100].freeze
    TURN_SECONDS = [30, 60, 90, 120, 300].freeze
    DEFAULT_PARTY_SIZE = 3
    DEFAULT_TURN_SECONDS = 60
    CLAUSES_PER_PAGE = 5
    CLAUSES_PER_SUMMARY_LINE = 4
    Setting = Struct.new(:label, :change)

    # Returns the chosen Duel::Rules, or nil if the player backs out.
    def self.choose(max_party_size)
      rules = Duel::Rules.new([DEFAULT_PARTY_SIZE, max_party_size].min, 0, true, DEFAULT_TURN_SECONDS, [])
      cursor = nil
      loop do
        settings = settings_for(rules, max_party_size)
        clauses_index = settings.size
        send_index = clauses_index + 1
        labels = settings.map(&:label) + [clauses_label(rules), _INTL("Send challenge"), _INTL("Cancel")]
        cursor = pbMessage(_INTL("Set the rules of the duel."), labels, labels.size, nil, cursor || send_index)
        return rules if cursor == send_index
        return nil if cursor > send_index
        rules = cursor == clauses_index ? edit_clauses(rules) : settings[cursor].change.call(rules)
      end
    end

    def self.settings_for(rules, max_party_size)
      [
        Setting.new(_INTL("Team size: {1}", rules.party_size), ->(r) { with(r, :party_size, r.party_size % max_party_size + 1) }),
        Setting.new(_INTL("Level: {1}", level_label(rules.level)), ->(r) { with(r, :level, next_value(LEVELS, r.level)) }),
        Setting.new(_INTL("Held items: {1}", held_items_label(rules)), ->(r) { with(r, :held_items, !r.held_items) }),
        Setting.new(_INTL("Turn timer: {1}s", rules.turn_seconds), ->(r) { with(r, :turn_seconds, next_value(TURN_SECONDS, r.turn_seconds)) })
      ]
    end

    def self.clauses_label(rules)
      _INTL("Clauses: {1} on", rules.clauses.size)
    end

    def self.edit_clauses(rules)
      pages = DuelClauses::ALL.each_slice(CLAUSES_PER_PAGE).to_a
      page = 0
      cursor = 0
      loop do
        clauses = pages[page]
        labels = clauses.map { |clause| clause_label(clause, rules) } + [_INTL("More ({1}/{2})", page + 1, pages.size), _INTL("Back")]
        cursor = pbMessage(_INTL("Choose the clauses."), labels, labels.size, nil, cursor)
        return rules if cursor > clauses.size
        if cursor == clauses.size
          page = (page + 1) % pages.size
        else
          rules = toggled(rules, clauses[cursor].id)
        end
      end
    end

    def self.clause_label(clause, rules)
      _INTL("{1}: {2}", _INTL(clause.label), rules.clauses.include?(clause.id) ? _INTL("On") : _INTL("Off"))
    end

    def self.toggled(rules, id)
      with(rules, :clauses, rules.clauses.include?(id) ? rules.clauses - [id] : rules.clauses + [id])
    end

    def self.with(rules, field, value)
      updated = rules.dup
      updated[field] = value
      updated
    end

    def self.level_label(level)
      level.positive? ? level.to_s : _INTL("Unchanged")
    end

    def self.held_items_label(rules)
      rules.held_items ? _INTL("Allowed") : _INTL("Banned")
    end

    # One message per entry, so that no window overflows.
    def self.summary(rules)
      base = _INTL("Team of {1}, level {2}, held items {3}, {4}s per turn.", rules.party_size,
                   level_label(rules.level), held_items_label(rules).downcase, rules.turn_seconds)
      labels = DuelClauses.named(rules.clauses).map { |clause| _INTL(clause.label) }
      [base] + labels.each_slice(CLAUSES_PER_SUMMARY_LINE).map { |slice| slice.join(", ") + "." }
    end

    def self.next_value(values, current)
      values[(values.index(current) + 1) % values.size]
    end
  end
end
