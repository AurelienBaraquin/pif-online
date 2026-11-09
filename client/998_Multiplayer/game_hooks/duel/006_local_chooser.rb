module Multiplayer
  # Asks the player for decisions through the game's own battle menus.
  module LocalChooser
    COMMAND_FIGHT = 0
    COMMAND_BAG = 1
    COMMAND_POKEMON = 2
    COMMAND_RUN = 3

    def self.choose(battle, index)
      battle.scene.with_turn_timer do
        loop do
          case battle.pbCommandMenu(index, true)
          when COMMAND_FIGHT then return take_choice(battle, index) if battle.pbFightMenu(index)
          when COMMAND_BAG then battle.pbDisplayPaused(_INTL("Items can't be used in a duel."))
          when COMMAND_POKEMON then return take_choice(battle, index) if battle.pbPartyMenu(index)
          when COMMAND_RUN then return nil if battle.pbDisplayConfirm(_INTL("Forfeit the duel?"))
          end
        end
      end
    end

    def self.replacement(battle, index)
      battle.scene.with_turn_timer { battle.pbPartyScreen(index, false, false) }
    end

    # The menus register the choice directly. It is read back and cleared, to be
    # applied when the server returns both players' choices.
    def self.take_choice(battle, index)
      kind, value = battle.choices[index]
      battle.pbClearChoice(index)
      return DuelLink::Choice.new("switch", value) if kind == :SwitchOut
      DuelLink::Choice.new("move", [value.to_i, 0].max)
    end
  end
end
