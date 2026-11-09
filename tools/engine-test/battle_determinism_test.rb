# Measures whether two game clients simulating the same duel stay identical.
# Each duel is played once with random legal choices, then replayed under every
# variant while comparing the state after each round. Global rand is seeded
# differently per run, so any draw outside pbRandom shows up as a divergence.

module BattleDeterminism
  RESULT_FILE = "test_result.txt"
  TIME_BUDGET = 100
  LEVEL = 50
  PARTY_SIZE = 6
  MAX_DEX = 251
  SWITCH_CHANCE = 15
  FUSION_CHANCE = 50
  HELD_ITEMS = %i[LEFTOVERS FOCUSSASH QUICKCLAW KINGSROCK LIFEORB BRIGHTPOWDER
                  MANKEYPAW SITRUSBERRY ROCKYHELMET CHOICESCARF].freeze

  Variant = Struct.new(:name, :mirrored, :fix_priority, :flip_owner)
  VARIANTS = [
    Variant.new("baseline (same view twice)", false, false, false),
    Variant.new("mirrored indices, unpatched", true, false, false),
    Variant.new("mirrored indices, priority tie patched", true, true, false),
    Variant.new("canonical indices, ownership flipped", false, false, true)
  ].freeze

  # Counts every draw from Ruby's global generator while a duel runs: each one
  # is a source of divergence between two clients.
  module UncontrolledRandomness
    SITES = Hash.new(0)
    @active = false

    class << self
      attr_accessor :active, :redirect
    end

    def self.record
      return unless active
      location = caller_locations(2, 3).find { |frame| !frame.path.end_with?("002_RubyUtilities.rb") }
      SITES["#{location&.path}:#{location&.lineno}"] += 1
    end
  end

  # The engine's debug scene lacks the display methods Infinite Fusion added.
  # None of them affects the simulation, so they all become no-ops here.
  class SilentScene < PokeBattle_DebugSceneNoLogging
    @missing = {}

    class << self
      attr_reader :missing
    end

    def method_missing(name, *_args)
      SilentScene.missing[name] = true
      nil
    end

    def respond_to_missing?(_name, _include_private = false)
      true
    end
  end

  class ScriptedBattle < PokeBattle_Battle
    attr_reader :trace, :recording

    def configure(seed:, variant:, recording:, chooser:)
      @duel_rng = Random.new(seed)
      @variant = variant
      @recording = recording
      @chooser = chooser
      @draws = 0
      @trace = []
    end

    def pbRandom(num)
      value = @duel_rng.rand(num)
      @draws += 1
      value = 1 - value if num == 2 && @in_priority && @variant.fix_priority
      value
    end

    def pbCalculatePriority(*args)
      @in_priority = true
      super
    ensure
      @in_priority = false
    end

    def pbOwnedByPlayer?(idx)
      return super unless @variant.flip_owner
      idx = idx.index if idx.respond_to?(:index)
      idx.odd?
    end

    def pbGainCosmeticsMoney
      0
    end

    def pbCommandPhase
      BattleDeterminism.touch
      @trace << signature
      super
    end

    def pbCommandPhaseLoop(is_player)
      return unless is_player
      @battlers.each_with_index do |battler, idx|
        next if !battler || @choices[idx][0] != :None || !pbCanShowCommands?(idx)
        apply_action(idx, next_action(idx) { choose_action(idx) })
      end
    end

    def pbSwitchInBetween(idx, _lax = false, _cancel = false)
      next_action(idx) { [:replace, legal_replacements(idx).sample(random: @chooser)] }[1]
    end

    def signature
      order = canonical_order
      [@turnCount, @draws, @decision, @field.weather, @field.terrain] + order.map { |idx| battler_signature(idx) }
    end

    private

    def canonical_order
      @variant.mirrored ? [1, 0] : [0, 1]
    end

    def canonical(idx)
      @variant.mirrored ? idx ^ 1 : idx
    end

    def next_action(idx)
      key = canonical(idx)
      if @variant.nil? || @chooser
        action = yield
        @recording[key] << action
        action
      else
        @recording[key].shift
      end
    end

    def choose_action(idx)
      switches = legal_replacements(idx, true)
      if !switches.empty? && @chooser.rand(100) < SWITCH_CHANCE
        return [:switch, switches.sample(random: @chooser)]
      end
      moves = (0...@battlers[idx].moves.length).select { |m| pbCanChooseMove?(idx, m, false) }
      return [:auto] if moves.empty?
      [:move, moves.sample(random: @chooser)]
    end

    def legal_replacements(idx, strict = false)
      (0...pbParty(idx).length).select do |party_idx|
        strict ? pbCanSwitch?(idx, party_idx, nil) : pbCanSwitchLax?(idx, party_idx, nil)
      end
    end

    def apply_action(idx, action)
      case action[0]
      when :move then pbRegisterMove(idx, action[1], false)
      when :switch then pbRegisterSwitch(idx, action[1])
      when :auto then pbAutoChooseMove(idx, false)
      end
    end

    # Effects hold battler indices, so they only compare between same-index views.
    def battler_signature(idx)
      b = @battlers[idx]
      base = [b.pokemon.species, b.hp, b.status, b.statusCount, b.item_id, b.ability_id,
              b.stages.dup, b.moves.map(&:pp), b.pokemonIndex,
              pbParty(idx).map { |p| [p.hp, p.status] }]
      @variant.mirrored ? base : base + [b.effects.dup]
    end
  end

  class StuckDuel < StandardError; end
  STUCK_AFTER = 10

  # Aborts a duel that stops making progress and records where it was stuck.
  def self.start_watchdog
    @last_progress = now
    Thread.new do
      loop do
        sleep(1)
        next if now - @last_progress < STUCK_AFTER
        report("stuck: #{Thread.main.backtrace.first(10).inspect[0, 900]}") if (@stuck_reports = @stuck_reports.to_i + 1) <= 3
        @last_progress = now
        Thread.main.raise(StuckDuel, "no progress")
      end
    end
  end

  def self.now
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  def self.touch
    @last_progress = now
  end

  def self.report(line)
    File.open(RESULT_FILE, "a") { |file| file.puts(line) }
  end

  def self.species_for(rng)
    head = rng.rand(1..MAX_DEX)
    return head if rng.rand(100) >= FUSION_CHANCE
    getFusionSpecies(rng.rand(1..MAX_DEX), head).id
  end

  def self.build_party(rng, move_ids)
    Array.new(PARTY_SIZE) do
      pokemon = Pokemon.new(species_for(rng), LEVEL)
      pokemon.item = HELD_ITEMS.sample(random: rng)
      pokemon.moves.clear
      move_ids.sample(4, random: rng).each { |move| pokemon.learn_move(move) }
      pokemon.calc_stats
      pokemon
    end
  end

  def self.trainer(name)
    NPCTrainer.new(name, GameData::TrainerType.keys.first)
  end

  def self.play(parties, seed, variant, recording, chooser)
    party_a, party_b = Marshal.load(Marshal.dump(parties))
    first, second = variant.mirrored ? [party_b, party_a] : [party_a, party_b]
    names = variant.mirrored ? %w[B A] : %w[A B]
    battle = ScriptedBattle.new(SilentScene.new, first, second,
                                [trainer(names[0])], [trainer(names[1])])
    battle.configure(seed: seed, variant: variant, recording: recording, chooser: chooser)
    battle.party1starts = [0]
    battle.party2starts = [0]
    battle.internalBattle = false
    battle.debug = true
    UncontrolledRandomness.active = true
    decision = begin
      battle.pbStartBattle
    ensure
      UncontrolledRandomness.active = false
    end
    decision = { 1 => 2, 2 => 1 }.fetch(decision, decision) if variant.mirrored
    [battle.trace << [:end, decision]].first
  end

  def self.compare(reference, trace)
    return nil if reference == trace
    round = (0...[reference.size, trace.size].max).find { |i| reference[i] != trace[i] }
    [round, first_difference(reference[round], trace[round])]
  end

  # A mirrored view records no effects (they hold battler indices), so its
  # reference must omit them too.
  def self.comparable_reference(reference, variant)
    return reference unless variant.mirrored
    reference.map do |entry|
      next entry if entry[0] == :end
      entry.map { |field| field.is_a?(Array) ? field[0...-1] : field }
    end
  end

  # Returns the path to the first differing leaf of two nested arrays.
  def self.first_difference(left, right, path = [])
    return [path, left, right] unless left.is_a?(Array) && right.is_a?(Array) && left.size == right.size
    index = (0...left.size).find { |i| left[i] != right[i] }
    index ? first_difference(left[index], right[index], path + [index]) : [path, :equal]
  end

  class Tally
    attr_accessor :duels, :divergent, :crashes, :first_rounds, :example, :causes

    def initialize
      @duels = @divergent = @crashes = 0
      @first_rounds = []
      @causes = Hash.new(0)
    end
  end

  def self.replay_variant(variant, parties, seed, script, reference, tally)
    Kernel.srand(rand(1 << 30))
    recording = script.transform_values(&:dup)
    trace = play(parties, seed, variant, recording, nil)
    tally.duels += 1
    difference = compare(comparable_reference(reference, variant), trace)
    return unless difference
    tally.divergent += 1
    tally.first_rounds << difference[0]
    tally.example ||= difference
  rescue StandardError => e
    tally.crashes += 1
    tally.causes["#{e.class}: #{e.message[0, 90]} @ #{(e.backtrace || []).first}"] += 1
    tally.example ||= "#{e.class}: #{e.message} #{(e.backtrace || []).first(4)}"
  end

  def self.run
    File.delete(RESULT_FILE) if File.exist?(RESULT_FILE)
    report("started")
    move_ids = GameData::Move.keys.select { |id| id.is_a?(Symbol) }
    tallies = VARIANTS.map { [_1, Tally.new] }.to_h
    deadline = now + TIME_BUDGET
    start_watchdog
    generation_failures = rounds = duel = 0
    while now < deadline
      duel += 1
      touch
      rng = Random.new(duel)
      begin
        parties = [build_party(rng, move_ids), build_party(rng, move_ids)]
        script = { 0 => [], 1 => [] }
        reference = play(parties, duel, VARIANTS[0], script, Random.new(duel * 7))
      rescue StandardError => e
        generation_failures += 1
        report("generation failure: #{e.class}: #{e.message} #{(e.backtrace || []).first(4)}") if generation_failures <= 3
        next
      end
      rounds += reference.size - 1
      VARIANTS.each { |variant| replay_variant(variant, parties, duel, script, reference, tallies[variant]) }
      Graphics.update
    end
    report("duels=#{tallies[VARIANTS[0]].duels} rounds=#{rounds} generation_failures=#{generation_failures}")
    tallies.each do |variant, tally|
      earliest = tally.first_rounds.tally.sort.first(5)
      report("#{variant.name}: divergent=#{tally.divergent}/#{tally.duels} crashes=#{tally.crashes} first_round=#{earliest}")
      report("  example: #{tally.example.inspect[0, 300]}") if tally.example
      tally.causes.sort_by { |_cause, count| -count }.first(4).each { |cause, count| report("  crash x#{count}: #{cause}") }
    end
    report("draws outside pbRandom: #{UncontrolledRandomness::SITES.sort_by { |_site, count| -count }.inspect}")
    report("scene methods stubbed: #{SilentScene.missing.keys.sort.join(", ")}")
    baseline = tallies[VARIANTS[0]]
    report(baseline.duels > 0 && baseline.divergent.zero? && baseline.crashes.zero? ? "PASS" : "FAIL baseline")
  rescue Exception => e
    report("FAIL #{e.class}: #{e.message}\n#{(e.backtrace || []).first(8).join("\n")}")
  ensure
    exit
  end
end

# The game defines a global rand that forwards to Kernel.rand.
class << Kernel
  alias_method :determinism_original_rand, :rand

  def rand(*args)
    battle = BattleDeterminism::UncontrolledRandomness.redirect
    return battle.pbRandom(*args) if battle
    BattleDeterminism::UncontrolledRandomness.record
    determinism_original_rand(*args)
  end
end

# The Mankey Paw check draws from global rand inside this method.
module SeededSuccessCheck
  def pbSuccessCheckPerHit(*args)
    BattleDeterminism::UncontrolledRandomness.redirect = @battle
    super
  ensure
    BattleDeterminism::UncontrolledRandomness.redirect = nil
  end
end
PokeBattle_Battler.prepend(SeededSuccessCheck)

class Array
  alias_method :determinism_original_sample, :sample
  alias_method :determinism_original_shuffle, :shuffle

  def sample(*args, **options)
    BattleDeterminism::UncontrolledRandomness.record unless options.key?(:random)
    determinism_original_sample(*args, **options)
  end

  def shuffle(**options)
    BattleDeterminism::UncontrolledRandomness.record unless options.key?(:random)
    determinism_original_shuffle(**options)
  end
end

# PBDebug.logonerr shows battle errors in a blocking dialog, then swallows them
# and carries on. Re-raising ends the duel, whose rescue records the error.
def pbPrintException(error)
  raise error
end

class Scene_Intro
  def main
    Game.start_new
    BattleDeterminism.run
  end
end
