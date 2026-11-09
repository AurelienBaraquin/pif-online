module Multiplayer
  # A battle scene that leaves as soon as the duel ends on the server, even
  # while a menu is open. It aborts only once: the battle's own cleanup also
  # updates this scene.
  class NetworkBattleScene < PokeBattle_Scene
    attr_writer :link

    def pbUpdate(cw = nil)
      super
      return if @aborted || @link.nil? || @link.ending.nil?
      @aborted = true
      @battle.pbAbort
    end
  end

  # Builds and plays a duel, isolating it from the player's save.
  module DuelRunner
    NEUTRALIZED_SWITCHES = %i[AUTOSAVE_WIN_SWITCH SWITCH_NO_LEVELS_MODE].freeze
    GUARD_SITE = "duel.battle"

    @running = false

    class << self
      attr_reader :running
    end

    def self.build_battle(link, scene, chooser, waiter)
      parties = link.parties.map { |party| PartyCodec.decode(party) }
      trainers = link.players.map { |player| NPCTrainer.new(player["name"], $Trainer.trainer_type) }
      battle = NetworkBattle.new(scene, parties[0], parties[1], [trainers[0]], [trainers[1]])
      battle.party1starts = [0]
      battle.party2starts = [0]
      battle.configure(link: link, chooser: chooser, waiter: waiter)
      battle
    end

    # Rules that would otherwise read the local save.
    def self.isolate(battle)
      battle.internalBattle = false
      battle.expGain = false
      battle.moneyGain = false
      battle.switchStyle = false
      battle.canLose = true
    end

    def self.run(link)
      @running = true
      outcome = with_neutralized_switches { play(link) }
      pbMessage(outcome_text(link, outcome))
    ensure
      @running = false
    end

    def self.play(link)
      scene = NetworkBattleScene.new
      scene.link = link
      battle = build_battle(link, scene, LocalChooser, -> { scene.pbUpdate })
      pbPrepareBattle(battle)
      isolate(battle)
      opponent = battle.opponent
      pbBattleAnimation(pbGetTrainerBattleBGM(opponent), 1, opponent) do
        pbSceneStandby { battle.pbStartBattle }
      end
      battle.report_result(-> { Graphics.update })
      Input.update
      link.ending
    rescue *Guard::RECOVERABLE, PokeBattle_Battle::BattleAbortedException => e
      Log.write("duel aborted: #{e.class}: #{e.message}\n#{(e.backtrace || []).first(8).join("\n")}")
      link.forfeit
      nil
    end

    def self.outcome_text(link, ending)
      return _INTL("The duel stopped because of an error.") unless ending
      return _INTL("The duel ended without a winner.") if ending.winner.nil?
      ending.winner == link.side ? _INTL("You won the duel!") : _INTL("You lost the duel.")
    end

    def self.with_neutralized_switches
      saved = NEUTRALIZED_SWITCHES.map { |name| Object.const_get(name) }.map { |id| [id, $game_switches[id]] }
      saved.each { |id, _value| $game_switches[id] = false }
      yield
    ensure
      saved.each { |id, value| $game_switches[id] = value }
    end

    # The game shows battle errors in a dialog, then carries on with the turn.
    # In a duel that would silently diverge, so errors must end the battle.
    def self.install_error_passthrough
      return if PBDebug.respond_to?(:multiplayer_original_logonerr)
      class << PBDebug
        alias_method :multiplayer_original_logonerr, :logonerr

        def logonerr(&block)
          return multiplayer_original_logonerr(&block) unless Multiplayer::DuelRunner.running
          yield
        end
      end
    end
  end
end
