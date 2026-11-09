module Multiplayer
  # Sends the Mankey Paw's roll, the one draw in battle that bypasses pbRandom,
  # through the duel's generator. Without this the two clients would diverge.
  module DuelRandom
    class << self
      attr_accessor :battle
    end

    def self.install
      return if Kernel.respond_to?(:multiplayer_original_rand)
      class << Kernel
        alias_method :multiplayer_original_rand, :rand

        def rand(*args)
          battle = Multiplayer::DuelRandom.battle
          battle ? battle.pbRandom(*args) : multiplayer_original_rand(*args)
        end
      end
    end

    module SeededSuccessCheck
      def pbSuccessCheckPerHit(*args)
        Multiplayer::DuelRandom.battle = @battle if @battle.is_a?(Multiplayer::NetworkBattle)
        super
      ensure
        Multiplayer::DuelRandom.battle = nil
      end
    end
  end

  # A duel simulated identically on both clients: battler indices are the same
  # on each (index 0 is side 0), so only the choices cross the network. Both
  # players' decisions come from the server, including the local one, so that
  # both simulations apply them at the same moment.
  class NetworkBattle < PokeBattle_Battle
    NO_ACTION = DuelLink::Choice.new("move", 0).freeze

    # chooser responds to choose(battle, indices), given the local battlers that
    # must act, returning a hash of battler index to DuelLink::Choice or nil to
    # forfeit, and to replacement(battle, index). waiter lets one frame pass.
    def configure(link:, chooser:, waiter:)
      @link = link
      @chooser = chooser
      @waiter = waiter
      @duel_rng = Random.new(link.seed)
    end

    def pbRandom(num)
      @duel_rng.rand(num)
    end

    def pbGainCosmeticsMoney
      0
    end

    def pbCanMegaEvolve?(_index)
      false
    end

    def pbCommandPhaseLoop(is_player)
      return unless is_player
      round = @turnCount + 1
      @link.send_hash(round - 1, state_hash) if round > 1
      send_local_choice(round)
      show_waiting unless @link.turn(round)
      choices = wait_for { @link.turn(round) }
      @battlers.each_index { |index| apply_action(index, choices[index & 1][index / 2]) }
    end

    # The engine asks for an Encored move's target only on side 0, and through a
    # menu even when applying the opponent's choice.
    def pbAutoChooseMove(index, show_messages = true)
      return super if singleBattle?
      battler = @battlers[index]
      encored = battler.pbEncoredMoveIndex
      return super unless encored >= 0 && pbCanChooseMove?(index, encored, false)
      move = battler.moves[encored]
      pbRegisterMove(index, encored, false)
      return true unless show_messages
      pbDisplayPaused(_INTL("{1} has to use {2}!", battler.name, move.name))
      pbChooseTarget(battler, move)
    end

    # The only entry point for a chosen replacement: Roar-like moves use the
    # engine's random path, which goes through pbRandom.
    def pbSwitchInBetween(index, _lax = false, _cancel = false)
      replacement(index)
    end

    # Waits for the end of the duel after reporting the local outcome. The
    # battle is over by then, so this only lets frames pass.
    def report_result(waiter = @waiter)
      return if @link.ending
      @link.send_result({ 1 => 0, 2 => 1 }[@decision])
      waiter.call until @link.ending
    end

    private

    def local_indices
      (0...@link.format.side_size).map { |slot| slot * 2 + @link.side }
    end

    def can_act?(index)
      pbCanShowCommands?(index) && @choices[index][0] == :None
    end

    def send_local_choice(round)
      indices = local_indices
      acting = indices.select { |index| can_act?(index) }
      chosen = acting.empty? ? {} : @chooser.choose(self, acting)
      if chosen.nil?
        @link.forfeit
        wait_for { nil }
      end
      @link.send_choice(round, indices.map { |index| chosen.fetch(index, NO_ACTION) })
    end

    # Runs on both clients in battler order, so one action can see the ones
    # applied before it (Pokémon already picked to switch in).
    def apply_action(index, action)
      return unless can_act?(index)
      return if action.action == "switch" && pbRegisterSwitch(index, action.index)
      registered = action.action == "move" && pbCanChooseMove?(index, action.index, false) && pbRegisterMove(index, action.index, false)
      pbAutoChooseMove(index, false) unless registered
      pbRegisterTarget(index, action.target) if action.target
    end

    def replacement(index)
      if index & 1 == @link.side
        @link.send_replacing
        @link.send_replacement(@chooser.replacement(self, index))
      else
        show_waiting
      end
      wait_for { @link.next_replacement(index & 1) }
    end

    def show_waiting
      pbDisplayBrief(_INTL("Waiting for opponent..."))
    end

    def wait_for
      loop do
        value = yield
        return value unless value.nil?
        pbAbort if @link.ending
        @waiter.call
      end
    end

    def plain_value?(value)
      value.nil? || value == true || value == false || value.is_a?(Integer) || value.is_a?(Symbol)
    end

    # Only plain values: other objects would print their memory address.
    def state_hash
      fields = @battlers.compact.map do |battler|
        [battler.pokemon.species, battler.hp, battler.status, battler.statusCount, battler.item_id, battler.ability_id,
         battler.moves.map(&:pp), battler.pokemonIndex, battler.stages.values,
         battler.attack, battler.defense, battler.spatk, battler.spdef, battler.speed,
         battler.effects.select { |value| plain_value?(value) }]
      end
      Zlib.crc32([@turnCount, @field.weather, @field.terrain, fields].inspect).to_s
    end
  end
end
