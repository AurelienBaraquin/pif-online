module Multiplayer
  # Turns a duelist's appearance, as received from the network, into the game's
  # own type. The values come from another player, so they are checked again.
  module DuelLook
    def self.from_wire(data)
      return nil unless data.is_a?(Hash)
      TrainerAppearance.new(LocalPlayer.integer(data["skin"], LocalPlayer::MAX_SKIN, 0),
                            LocalPlayer.asset(data["hat"]), LocalPlayer.asset(data["clothes"]), LocalPlayer.asset(data["hair"]),
                            color(data["hair_color"]), color(data["clothes_color"]), color(data["hat_color"]),
                            LocalPlayer.asset(data["hat2"]), color(data["hat2_color"]))
    end

    def self.color(value)
      LocalPlayer.integer(value, LocalPlayer::MAX_COLOR, -LocalPlayer::MAX_COLOR)
    end
  end

  # A battle scene that leaves as soon as the duel ends on the server. The
  # check runs from Graphics.update because the party and summary screens have
  # their own loops. It is armed only between the scene's start and its end, so
  # the abort is raised at most once and never during cleanup.
  class NetworkBattleScene < PokeBattle_Scene
    TIMER_SITE = "duel.timer"

    attr_writer :link

    def pbStartBattle(battle)
      super
      @abort_armed = true
    end

    def pbEndBattle(result)
      @abort_armed = false
      DuelOverlays.close_all
      super
    end

    def with_turn_timer
      @link.restart_turn_clock
      @turn_timer = DuelTurnTimer.new(@link)
      yield
    ensure
      @turn_timer&.dispose
      @turn_timer = nil
    end

    # Whichever side the viewer plays, the near trainer is the viewer.
    def pbCreateTrainerBackSprite(idx_trainer, trainer_type, num_trainers = 1)
      super
      dress(@sprites["player_#{idx_trainer + 1}"], @link.side)
    end

    def pbCreateTrainerFrontSprite(idx_trainer, trainer_type, num_trainers = 1, sprite_override = nil, custom_appearance = nil)
      super
      sprite = @sprites["trainer_#{idx_trainer + 1}"]
      dress(sprite, 1 - @link.side)
      return unless sprite.bitmap
      sprite.ox = sprite.src_rect.width / 2
      sprite.oy = sprite.bitmap.height
    end

    def on_frame
      Guard.run(TIMER_SITE) { @turn_timer&.update }
      return unless @abort_armed && @link.ending
      @abort_armed = false
      @battle.pbAbort
    end

    private

    # Keeps the sprite the engine created when the appearance cannot be drawn.
    def dress(sprite, side)
      look = DuelLook.from_wire(@link.players[side]["appearance"])
      return unless look
      sprite.setBitmapDirectly(generate_front_trainer_sprite_bitmap_from_appearance(look, false))
      sprite.src_rect.set(0, 0, sprite.bitmap.width, sprite.bitmap.height)
    rescue *Guard::RECOVERABLE => e
      Log.write("trainer sprite fallback for side #{side}: #{e.class}: #{e.message}")
    end
  end

  # Builds and plays a duel, isolating it from the player's save.
  module DuelRunner
    NEUTRALIZED_SWITCHES = %i[AUTOSAVE_WIN_SWITCH SWITCH_NO_LEVELS_MODE SWITCH_IS_REMATCH SWITCH_RANDOM_HELD_ITEMS].freeze
    # Counts the spirits released when a Pokémon faints, which a duel must not advance.
    PRESERVED_VARIABLES = %i[VAR_ODDKEYSTONE_NB].freeze
    GUARD_SITE = "duel.battle"
    ILLEGAL_TEXT = "The duel was cancelled because a team breaks the rules."
    # Wording by server reason. A reason lacking an outcome uses FALLBACK_TEXTS.
    ENDING_TEXTS = {
      "finished" => { won: "You won the duel!", lost: "You lost the duel.", none: "The duel ended in a draw." },
      "forfeit" => { won: "{1} forfeited. You won the duel!", lost: "You forfeited the duel." },
      "disconnect" => { won: "{1} disconnected. You won the duel!" },
      "timeout" => { won: "{1} ran out of time. You won the duel!", lost: "You ran out of time. You lost the duel.",
                     none: "Time ran out for both players. The duel ended without a winner." },
      "desync" => { none: "The duel was cancelled because the two games disagreed." },
      Duel::REASON_ILLEGAL => { none: ILLEGAL_TEXT },
      Duel::REASON_CONNECTION_LOST => { none: "The connection to the server was lost. The duel was cancelled." }
    }.freeze
    FALLBACK_TEXTS = { won: "You won the duel!", lost: "You lost the duel.", none: "The duel ended without a winner." }.freeze

    @running = false
    @scene = nil

    class << self
      attr_reader :running, :scene
    end

    def self.on_frame
      @scene&.on_frame
    end

    def self.build_battle(link, scene, chooser, waiter)
      parties = link.parties.map { |party| PartyCodec.decode(party) }
      trainers = link.players.map { |player| NPCTrainer.new(display_name(player), $Trainer.trainer_type) }
      battle = NetworkBattle.new(scene, parties[0], parties[1], [trainers[0]], [trainers[1]])
      battle.party1starts = [0]
      battle.party2starts = [0]
      battle.configure(link: link, chooser: chooser, waiter: waiter)
      pbPrepareBattle(battle)
      isolate(battle)
      DuelClauses.apply_to(battle, link.rules["clauses"])
      battle
    end

    # Undoes what pbPrepareBattle derives from the local save and map: the size
    # from the options, the weather and surroundings from the overworld, and
    # any battle rule left behind by an event.
    def self.isolate(battle)
      battle.setBattleMode("single")
      battle.defaultWeather = :None
      battle.defaultTerrain = :None
      battle.environment = :None
      battle.caughtOffGuard = false
      battle.internalBattle = false
      battle.expGain = false
      battle.moneyGain = false
      battle.switchStyle = false
      battle.canLose = true
    end

    def self.run(link)
      @running = true
      outcome = with_neutralized_save { play(link) }
      pbMessage(outcome_text(link, outcome))
    ensure
      @running = false
      @scene = nil
    end

    # The server cannot check every rule: an opponent's illegal team stops here.
    def self.refuse(link)
      link.reject
      Graphics.update until link.ending
      link.ending
    end

    def self.play(link)
      return refuse(link) if DuelClauses.violation(link.parties[1 - link.side], link.rules["clauses"])
      scene = SideOneDisplay.scene_for(link)
      scene.link = link
      @scene = scene
      battle = build_battle(link, scene, LocalChooser, -> { scene.pbUpdate })
      opponent = battle.opponent
      pbBattleAnimation(pbGetTrainerBattleBGM(opponent), 1, opponent) do
        SideOneDisplay.during(link) { pbSceneStandby { battle.pbStartBattle } }
      end
      battle.report_result(-> { Graphics.update })
      Input.update
      link.ending
    rescue *Guard::RECOVERABLE, PokeBattle_Battle::BattleAbortedException => e
      Log.write("duel aborted: #{e.class}: #{e.message}\n#{(e.backtrace || []).first(8).join("\n")}")
      link.forfeit unless link.ending
      link.ending
    end

    def self.outcome_text(link, ending)
      return _INTL("The duel stopped because of an error.") unless ending
      outcome = ending.winner.nil? ? :none : (ending.winner == link.side ? :won : :lost)
      template = ENDING_TEXTS.fetch(ending.reason, {}).fetch(outcome) { FALLBACK_TEXTS[outcome] }
      _INTL(template, opponent_name(link))
    end

    def self.opponent_name(link)
      display_name(link.players[1 - link.side])
    end

    # The name goes into messages, whose text is interpreted: a backslash in a
    # player's name would start a control code.
    def self.display_name(player)
      player["name"].to_s.delete("\\")
    end

    # A duel must neither read nor change the save. The battle code writes to
    # $Trainer and $PokemonBag directly (statistics, challenges, restocking
    # consumed items), so it plays against a disposable copy and an empty bag.
    def self.with_neutralized_save
      trainer = $Trainer
      bag = $PokemonBag
      no_reviving = $PokemonSystem.no_reviving
      switches = NEUTRALIZED_SWITCHES.map { |name| Object.const_get(name) }.map { |id| [id, $game_switches[id]] }
      variables = PRESERVED_VARIABLES.map { |name| Object.const_get(name) }.map { |id| [id, $game_variables[id]] }
      $Trainer = Marshal.load(Marshal.dump(trainer))
      $PokemonBag = PokemonBag.new
      $PokemonSystem.no_reviving = false
      switches.each { |id, _value| $game_switches[id] = false }
      yield
    ensure
      $Trainer = trainer
      $PokemonBag = bag
      $PokemonSystem.no_reviving = no_reviving
      switches&.each { |id, value| $game_switches[id] = value }
      variables&.each { |id, value| $game_variables[id] = value }
    end

    # The game shows battle errors in a dialog, then carries on with the turn.
    # In a duel that would silently diverge, so errors must end the battle. A
    # prepended module survives an F12 reload, which redefines PBDebug.logonerr.
    module ErrorPassthrough
      def logonerr(&block)
        return super unless DuelRunner.running
        yield
      end
    end
  end
end
