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
    SIDES = [0, 1].freeze

    # chooser responds to choose(battle, index), returning a DuelLink::Choice or
    # nil to forfeit, and to replacement(battle, index). waiter lets one frame pass.
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
      choices = wait_for { @link.turn(round) }
      SIDES.each { |index| apply_choice(index, choices[index]) }
    end

    def pbSwitchInBetween(index, _lax = false, _cancel = false)
      replacement(index)
    end

    def pbGetReplacementPokemonIndex(index, _random = false)
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

    def send_local_choice(round)
      index = @link.side
      choice = pbCanShowCommands?(index) && @choices[index][0] == :None ? @chooser.choose(self, index) : NO_ACTION
      if choice.nil?
        @link.forfeit
        wait_for { nil }
      end
      @link.send_choice(round, choice)
    end

    def apply_choice(index, choice)
      return if @choices[index][0] != :None || !pbCanShowCommands?(index)
      if choice.action == "switch" && pbRegisterSwitch(index, choice.index)
        return
      end
      return if choice.action == "move" && pbCanChooseMove?(index, choice.index, false) && pbRegisterMove(index, choice.index, false)
      pbAutoChooseMove(index, false)
    end

    def replacement(index)
      @link.send_replacement(@chooser.replacement(self, index)) if index == @link.side
      wait_for { @link.next_replacement(index) }
    end

    def wait_for
      loop do
        value = yield
        return value unless value.nil?
        pbAbort if @link.ending
        @waiter.call
      end
    end

    # Only plain values: other objects would print their memory address.
    def state_hash
      fields = @battlers.compact.map do |battler|
        [battler.pokemon.species, battler.hp, battler.status, battler.statusCount, battler.item_id, battler.ability_id,
         battler.moves.map(&:pp), battler.pokemonIndex, battler.stages.values]
      end
      Zlib.crc32([@turnCount, @field.weather, @field.terrain, fields].inspect).to_s
    end
  end
end
