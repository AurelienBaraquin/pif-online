module Multiplayer
  # Asks the player for decisions through the game's own battle menus.
  module LocalChooser
    COMMAND_FIGHT = 0
    COMMAND_BAG = 1
    COMMAND_POKEMON = 2
    COMMAND_RUN = 3
    COMMAND_BACK = -1

    # Walks the battlers like the engine's command loop: going back clears the
    # previous battler's choice, and the choices stay registered meanwhile so
    # that the engine refuses a Pokémon the partner already picked to switch in.
    def self.choose(battle, indices)
      battle.scene.with_turn_timer do
        position = 0
        while position < indices.size
          case battler_command(battle, indices[position], position.zero?)
          when :forfeit
            indices.each { |index| battle.pbCancelChoice(index) }
            return nil
          when :back
            position -= 1
            battle.pbCancelChoice(indices[position])
          else
            position += 1
          end
        end
        indices.to_h { |index| [index, take_choice(battle, index)] }
      end
    end

    # Returns :chosen, :back or :forfeit.
    def self.battler_command(battle, index, first)
      loop do
        command = battle.pbCommandMenu(index, first)
        if command.positive? && battle.battlers[index].effects[PBEffects::SkyDrop] >= 0
          battle.pbDisplay(_INTL("Sky Drop won't let {1} go!", battle.battlers[index].pbThis(true)))
          next
        end
        case command
        when COMMAND_FIGHT then return :chosen if battle.pbFightMenu(index)
        when COMMAND_BAG then battle.pbDisplayPaused(_INTL("Items can't be used in a duel."))
        when COMMAND_POKEMON
          if battle.pbPartyMenu(index)
            battle.scene.setLastCommandIndex(index, COMMAND_FIGHT)
            return :chosen
          end
        when COMMAND_RUN then return :forfeit if battle.pbDisplayConfirm(_INTL("Forfeit the duel?"))
        when COMMAND_BACK then return :back unless first
        end
        battle.pbCancelChoice(index)
      end
    end

    def self.replacement(battle, index)
      battle.scene.with_turn_timer { battle.pbPartyScreen(index, true, false) }
    end

    # The menus register the choice directly. It is read back and cleared, to be
    # applied when the server returns both players' choices.
    def self.take_choice(battle, index)
      kind, value, _move, target = battle.choices[index]
      battle.pbClearChoice(index)
      return DuelLink::Choice.new("switch", value) if kind == :SwitchOut
      DuelLink::Choice.new("move", [value.to_i, 0].max, target >= 0 ? target : nil)
    end
  end
end
