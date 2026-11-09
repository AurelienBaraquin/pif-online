module Multiplayer
  # The window opened by interacting with another player. A new interaction is
  # one more entry in OPTIONS.
  module InteractionMenu
    Option = Struct.new(:label, :action)
    MAX_PARTY_SIZE = 6

    def self.options
      [Option.new(_INTL("Duel"), method(:start_duel))]
    end

    # Opens the window if the local player faces a remote player.
    def self.open_if_facing_player
      presence = Runtime.feature(Presence::FEATURE_NAME)
      return unless presence
      map_id, x, y = pbFacingTile
      player = presence.players_on(map_id).find { |candidate| candidate.state.x == x && candidate.state.y == y }
      show(player) if player
    end

    def self.show(player)
      entries = options
      labels = entries.map(&:label) + [_INTL("Cancel")]
      choice = pbMessage(_INTL("What do you want to do with {1}?", player.name), labels, labels.size)
      entries[choice]&.action&.call(player)
    end

    def self.start_duel(player)
      available = DuelParty.available_count
      return pbMessage(_INTL("You have no Pokémon able to battle.")) if available.zero?
      duel = Runtime.feature(Duel::FEATURE_NAME)
      return pbMessage(_INTL("You already have a duel in progress.")) unless duel&.idle?
      rules = RulesMenu.choose([available, MAX_PARTY_SIZE].min)
      return unless rules
      return if DuelPrompts.warn_if_illegal(rules)
      duel.challenge(player.id, rules)
      pbMessage(_INTL("Challenge sent to {1}.", player.name))
    end
  end
end
