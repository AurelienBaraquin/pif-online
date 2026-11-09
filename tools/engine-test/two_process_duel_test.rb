# Plays duels between two separate game processes through the real server. Each
# process takes its role from PIF_TEST_ROLE, deliberately makes its save differ
# from the other one's in everything a battle could read, and checks that no
# duel desyncs and that none changes the save. Loaded after network_duel_test.rb.

module TwoProcessDuelTest
  ROLE = ENV.fetch("PIF_TEST_ROLE")
  RESULT_FILE = "test_result_#{ROLE}.txt"
  CHALLENGER = "red"
  TIME_BUDGET = 330
  STARTUP_WAIT = 120
  DUEL_WAIT = 30
  DUEL_LIMIT = 90
  MINIMUM_DUELS = 10
  MEETING_MAP = 1
  MEETING_STATE = Multiplayer::Presence::State.new(MEETING_MAP, 0, 0, 2, 1)
  ROTATION = NetworkDuelTest::ROTATION
  # Advances with every frame, whatever the duel does.
  CLOCK_FIELDS = %i[@newFrameCount].freeze
  # Draws of the global generator that cannot reach the simulation: nothing in
  # 011_Battle reads the wild held item that FusedSpecies picks.
  HARMLESS_DRAW_SITE = "FusedSpecies.rb"
  BAG_ITEMS = BattleDeterminism::HELD_ITEMS + %i[ODDKEYSTONE EXPALL]

  Profile = Struct.new(:switch, :variable, :badge, :money, :id, :battle_type, :challenge_option, :battle_style,
                       :overworld_flag, :party_size, :bag_quantity, :battle_rules, :screen_weather, :seed)
  PROFILES = {
    "red" => Profile.new(true, 77, true, 999_999, 11_111, 1, true, 1, true, 6, 9,
                         { "size" => "double", "defaultWeather" => :Hail, "environment" => :Cave,
                           "defaultTerrain" => :Electric, "surprise" => true }, :None, 101),
    "blue" => Profile.new(false, 0, false, 12, 22_222, 0, false, 0, false, 2, 0, {}, :Rain, 202)
  }.freeze

  def self.report(line)
    File.open(RESULT_FILE, "a") { |file| file.puts(line) }
  end

  def self.now
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  # Makes the local save as different as possible from the other process's.
  module SaveDifferences
    def self.apply(profile, move_ids)
      apply_game_state(profile)
      apply_trainer(profile, move_ids)
      apply_options(profile)
      apply_bag(profile)
      $PokemonGlobal.bicycle = profile.overworld_flag
      $game_screen.weather(profile.screen_weather, 9, 0)
      $PokemonTemp.battleRules.clear
      $PokemonTemp.battleRules.merge!(profile.battle_rules)
    end

    def self.apply_game_state(profile)
      (1...$data_system.switches.size).each { |id| $game_switches[id] = profile.switch }
      (1...$data_system.variables.size).each { |id| $game_variables[id] = profile.variable }
    end

    def self.apply_trainer(profile, move_ids)
      $Trainer.badges = Array.new(Settings::NB_BADGES, profile.badge)
      $Trainer.money = profile.money
      $Trainer.id = profile.id
      $Trainer.party = BattleDeterminism.build_party(Random.new(profile.seed), move_ids).first(profile.party_size)
    end

    def self.apply_options(profile)
      $PokemonSystem.battle_type = profile.battle_type
      $PokemonSystem.battlestyle = profile.battle_style
      $PokemonSystem.level_caps = profile.battle_type
      $PokemonSystem.no_reviving = profile.challenge_option
      $PokemonSystem.no_healing_items_battles = profile.challenge_option
    end

    def self.apply_bag(profile)
      return if profile.bag_quantity.zero?
      BAG_ITEMS.each { |item| $PokemonBag.pbStoreItem(item, profile.bag_quantity) if GameData::Item.exists?(item) }
    end
  end

  # Field-by-field digests of everything a save file keeps.
  module SaveSnapshot
    def self.take
      {
        "trainer" => fields($Trainer), "bag" => fields($PokemonBag), "global" => fields($PokemonGlobal),
        "options" => fields($PokemonSystem), "switches" => fields($game_switches), "variables" => variables
      }
    end

    # The game's clock maintains this variable by itself as time passes.
    def self.variables
      data = $game_variables.instance_variable_get(:@data).dup
      data[UnrealTime::EXTRA_SECONDS] = nil
      { :@data => Marshal.dump(data) }
    end

    def self.fields(object)
      object.instance_variables.reject { |name| CLOCK_FIELDS.include?(name) }
            .to_h { |name| [name, Marshal.dump(object.instance_variable_get(name))] }
    end

    # Names the changed slots of an array field, such as one game variable.
    def self.detail(before, after)
      old_value = Marshal.load(before)
      new_value = Marshal.load(after)
      return "" unless old_value.is_a?(Array) && new_value.is_a?(Array)
      changed = (0...[old_value.size, new_value.size].max).reject { |i| old_value[i] == new_value[i] }
      "[#{changed.first(5).map { |i| "#{i}:#{old_value[i].inspect}->#{new_value[i].inspect}" }.join(",")}]"
    end

    def self.differences(before, after)
      before.flat_map do |section, values|
        (values.keys | after[section].keys).reject { |name| values[name] == after[section][name] }
                                           .map { |name| "#{section}.#{name}#{detail(values[name], after[section][name])}" }
      end
    end
  end

  class Match
    attr_reader :tally, :rounds, :save_changes, :format_counts

    def initialize(peer, presence)
      @peer = peer
      @presence = presence
      @tally = Hash.new(0)
      @format_counts = Hash.new(0)
      @rounds = 0
      @save_changes = Hash.new(0)
      @baseline = SaveSnapshot.take
      @move_ids = GameData::Move.keys.select { |id| id.is_a?(Symbol) }
    end

    def duels
      @tally.values.sum
    end

    # Plays until the time budget runs out or the other process leaves.
    def play_all(deadline)
      rng = Random.new(PROFILES[ROLE].seed)
      while (link = next_link(rng, deadline))
        play_duel(link, rng.rand(1 << 30))
        record_outcome(link)
      end
    end

    private

    def pump
      Graphics.update
      @peer.client.tick
    end

    def wait_for(seconds, description)
      limit = TwoProcessDuelTest.now + seconds
      until (value = yield)
        raise "timeout: #{description}" if TwoProcessDuelTest.now > limit
        pump
      end
      value
    end

    def other_player
      @presence.players_on(MEETING_MAP).first
    end

    def next_link(rng, deadline)
      @peer.source.party = Multiplayer::PartyCodec.encode(BattleDeterminism.build_party(rng, @move_ids))
      ROLE == CHALLENGER ? challenge(deadline) : answer(deadline)
    end

    # A decline only means the other process is still leaving the last duel.
    def challenge(deadline)
      while TwoProcessDuelTest.now < deadline
        opponent = wait_for(DUEL_WAIT, "opponent") { other_player }
        wait_for(DUEL_WAIT, "idle") { @peer.duel.idle? }
        @peer.duel.challenge(opponent.id, ROTATION[duels % ROTATION.size])
        outcome = wait_for(DUEL_WAIT, "duel start") { @peer.duel.take_start || @peer.duel.take_notice }
        return outcome if outcome.is_a?(Multiplayer::DuelLink)
      end
      nil
    end

    def answer(deadline)
      invitation = wait_for(STARTUP_WAIT, "invitation") do
        @peer.duel.take_invitation || (:over if other_player.nil? || TwoProcessDuelTest.now > deadline)
      end
      return nil if invitation == :over
      @peer.duel.respond(invitation, true)
      wait_for(DUEL_WAIT, "duel start") { @peer.duel.take_start }
    end

    def play_duel(link, seed)
      Multiplayer::DuelRunner.with_neutralized_save { simulate(link, seed) }
    ensure
      @save_changes = SaveSnapshot.differences(@baseline, SaveSnapshot.take).reduce(@save_changes) do |changes, field|
        changes.merge(field => changes[field] + 1)
      end
    end

    def simulate(link, seed)
      player = NetworkDuelTest::Player.new(link, NetworkDuelTest::ScriptedChooser.new(seed))
      $game_temp.in_battle = true
      BattleDeterminism::UncontrolledRandomness.active = true
      limit = TwoProcessDuelTest.now + DUEL_LIMIT
      while player.alive?
        raise "duel too long" if TwoProcessDuelTest.now > limit
        pump
        player.resume
      end
      raise "battle error: #{player.error}" if player.error
      @rounds += player.round
    ensure
      BattleDeterminism::UncontrolledRandomness.active = false
      $game_temp.in_battle = false
    end

    def record_outcome(link)
      reason = link.ending.reason
      @tally = @tally.merge(reason => @tally[reason] + 1)
      @format_counts = @format_counts.merge(link.rules["format"] => @format_counts[link.rules["format"]] + 1)
      TwoProcessDuelTest.report("duel #{duels}: #{reason} winner=#{link.ending.winner}") unless reason == "finished"
    end
  end

  def self.meet(peer, presence)
    limit = now + STARTUP_WAIT
    until peer.client.ready? && presence.players_on(MEETING_MAP).first
      raise "timeout: other process never appeared" if now > limit
      presence.publish(MEETING_STATE, Multiplayer::LocalPlayer.appearance, [MEETING_MAP])
      Graphics.update
      peer.client.tick
    end
  end

  def self.draw_sites
    BattleDeterminism::UncontrolledRandomness::SITES.sort_by { |_site, count| -count }
  end

  def self.verdict(match)
    return "FAIL only #{match.duels} duels" if match.duels < MINIMUM_DUELS
    return "FAIL no doubles duel" if match.format_counts["doubles"].zero?
    return "FAIL endings #{match.tally}" unless match.tally.keys == ["finished"]
    return "FAIL save changed: #{match.save_changes.keys.join(", ")}" unless match.save_changes.empty?
    harmful = draw_sites.reject { |site, _count| site.include?(HARMLESS_DRAW_SITE) }
    return "FAIL draws outside pbRandom: #{harmful}" unless harmful.empty?
    "PASS"
  end

  def self.run
    File.delete(RESULT_FILE) if File.exist?(RESULT_FILE)
    report("started role=#{ROLE}")
    Multiplayer.send(:remove_const, :LOG_FILE)
    Multiplayer.const_set(:LOG_FILE, "multiplayer_#{ROLE}.log")
    profile = PROFILES.fetch(ROLE)
    Kernel.srand(profile.seed)
    SaveDifferences.apply(profile, GameData::Move.keys.select { |id| id.is_a?(Symbol) })
    peer = NetworkDuelTest::Peer.new(ROLE)
    presence = Multiplayer::Presence.new(peer.client)
    meet(peer, presence)
    match = Match.new(peer, presence)
    match.play_all(now + TIME_BUDGET)
    peer.client.stop
    report("duels=#{match.duels} rounds=#{match.rounds} formats=#{match.format_counts} endings=#{match.tally}")
    report("global draws: #{draw_sites}")
    report("save changes: #{match.save_changes}")
    report(verdict(match))
  rescue Exception => e
    report("FAIL #{e.class}: #{e.message}\n#{(e.backtrace || []).first(8).join("\n")}")
  ensure
    exit
  end
end

class Scene_Intro
  def main
    Game.start_new
    TwoProcessDuelTest.run
  end
end
