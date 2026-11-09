# Plays complete duels between two NetworkBattle instances linked through the
# real server, inside one game process. Each battle runs in a Fiber that yields
# whenever it waits for the network. Loaded after battle_determinism_test.rb.

module NetworkDuelTest
  RESULT_FILE = "test_result.txt"
  TIME_BUDGET = 110
  FRAMES_PER_STEP = 3
  ADDRESS = Multiplayer::Config.new("127.0.0.1", 7777)
  # Every clause that only changes the simulation: the random parties must stay legal.
  SIMULATION_CLAUSES = %w[sleep freeze ohko evasion perish skill_swap sonic_boom].freeze
  RULES = Multiplayer::Duel::Rules.new(6, 0, true, 60, SIMULATION_CLAUSES)
  DOUBLES = Multiplayer::Duel::Rules.new(6, 0, true, 60, [], "doubles")
  DOUBLES_WITH_CLAUSES = Multiplayer::Duel::Rules.new(6, 0, true, 60, SIMULATION_CLAUSES, "doubles")
  ROTATION = [DOUBLES, DOUBLES_WITH_CLAUSES, RULES].freeze
  # Out of this many targeted moves, one aims anywhere, to reach the engine's
  # fallbacks, and one lets the simulation pick.
  WILD_TARGET_CHANCE = 5
  AUTO_TARGET_CHANCE = 5
  INTERRUPT_ROUND = 3
  SWITCH_CHANCE = 15

  class PartySource
    attr_accessor :party

    def for_rules(_rules)
      @party
    end

    def appearance
      {}
    end
  end

  # Random legal decisions. Returning nil from choose forfeits.
  class ScriptedChooser
    def initialize(seed, forfeit_round: nil)
      @rng = Random.new(seed)
      @forfeit_round = forfeit_round
    end

    def choose(battle, indices)
      return nil if @forfeit_round && battle.turnCount + 1 >= @forfeit_round
      chosen = indices.to_h { |index| [index, action_for(battle, index)] }
      indices.each { |index| battle.pbClearChoice(index) }
      chosen
    end

    # Registers a switch as the menus do, so the partner cannot pick the same Pokémon.
    def action_for(battle, index)
      party_slots = (0...battle.pbParty(index).length).select { |slot| battle.pbCanSwitch?(index, slot, nil) }
      if !party_slots.empty? && @rng.rand(100) < SWITCH_CHANCE
        slot = party_slots.sample(random: @rng)
        battle.pbRegisterSwitch(index, slot)
        return Multiplayer::DuelLink::Choice.new("switch", slot)
      end
      moves = (0...battle.battlers[index].moves.length).select { |slot| battle.pbCanChooseMove?(index, slot, false) }
      move = moves.sample(random: @rng) || 0
      Multiplayer::DuelLink::Choice.new("move", move, target_for(battle, index, move))
    end

    def target_for(battle, index, move_slot)
      return nil if battle.singleBattle?
      roll = @rng.rand(WILD_TARGET_CHANCE + AUTO_TARGET_CHANCE)
      return nil if roll < AUTO_TARGET_CHANCE - 1
      slots = (0...battle.battlers.length).to_a
      return slots.sample(random: @rng) if roll >= WILD_TARGET_CHANCE + AUTO_TARGET_CHANCE - 1
      move = battle.battlers[index].moves[move_slot]
      return nil unless move
      data = move.pbTarget(battle.battlers[index])
      slots.select { |slot| battle.pbMoveCanTarget?(index, slot, data) }.sample(random: @rng)
    end

    def replacement(battle, index)
      (0...battle.pbParty(index).length).select { |slot| battle.pbCanSwitchLax?(index, slot, nil) }.sample(random: @rng)
    end
  end

  class Peer
    attr_reader :client, :duel, :source

    def initialize(name)
      @source = PartySource.new
      @client = Multiplayer::Client.new(ADDRESS, name)
      @duel = Multiplayer::Duel.new(@client, @source)
      @client.start
    end
  end

  class Player
    attr_reader :link, :error

    def initialize(link, chooser)
      @link = link
      scene = BattleDeterminism::SilentScene.new
      @battle = Multiplayer::DuelRunner.build_battle(link, scene, chooser, -> { Fiber.yield })
      @battle.debug = true
      @fiber = Fiber.new { play }
    end

    def round
      @battle.turnCount + 1
    end

    def alive?
      @fiber.alive?
    end

    def resume
      @fiber.resume if alive?
    end

    private

    def play
      @battle.pbStartBattle
      @battle.report_result
    rescue Exception => e
      @error = "#{e.class}: #{e.message} #{(e.backtrace || []).first(6)}"
    end
  end

  def self.report(line)
    File.open(RESULT_FILE, "a") { |file| file.puts(line) }
  end

  def self.now
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  def self.pump(peers, frames = FRAMES_PER_STEP)
    frames.times do
      Graphics.update
      peers.each { |peer| peer.client.tick }
    end
  end

  def self.wait_until(peers, description)
    deadline = now + 8
    until (value = yield)
      raise "timeout: #{description}" if now > deadline
      pump(peers, 1)
    end
    value
  end

  def self.connect(names)
    peers = names.map { |name| Peer.new(name) }
    wait_until(peers, "welcome") { peers.all? { |peer| peer.client.ready? } }
    peers
  end

  def self.start_links(peers, rng, move_ids, rules = RULES)
    peers.each { |peer| peer.source.party = Multiplayer::PartyCodec.encode(BattleDeterminism.build_party(rng, move_ids)) }
    red, blue = peers
    red.duel.challenge(blue.client.player_id, rules)
    invitation = wait_until(peers, "invitation") { blue.duel.take_invitation }
    blue.duel.respond(invitation, true)
    peers.map { |peer| wait_until(peers, "start") { peer.duel.take_start } }
  end

  def self.play(peers, players, on_step = nil)
    deadline = now + 45
    while players.any?(&:alive?)
      raise "duel too long" if now > deadline
      pump(peers)
      players.each(&:resume)
      on_step&.call
    end
    players.each { |player| raise "battle error: #{player.error}" if player.error }
  end

  def self.finished_duel(peers, rng, move_ids, seed, tally, rules)
    links = start_links(peers, rng, move_ids, rules)
    players = links.map.with_index { |link, side| Player.new(link, ScriptedChooser.new(seed + side)) }
    play(peers, players)
    reasons = links.map { |link| link.ending&.reason }
    tally["#{rules.format}:#{reasons.uniq.join("/")}"] += 1
    return if reasons == %w[finished finished] && links[0].ending.winner == links[1].ending.winner
    raise "unexpected endings: #{links.map { |link| link.ending.to_a }}"
  end

  def self.forfeit_duel(peers, rng, move_ids)
    links = start_links(peers, rng, move_ids)
    players = [Player.new(links[0], ScriptedChooser.new(1, forfeit_round: INTERRUPT_ROUND)), Player.new(links[1], ScriptedChooser.new(2))]
    play(peers, players)
    raise "bad forfeit: #{links[1].ending.to_a}" unless links[1].ending.to_a == [1, "forfeit"]
    report("OK   forfeit ends the duel for both, opponent wins")
  end

  def self.disconnect_duel(rng, move_ids)
    peers = connect(%w[Stayer Leaver])
    links = start_links(peers, rng, move_ids)
    players = links.map.with_index { |link, side| Player.new(link, ScriptedChooser.new(side + 5)) }
    left = false
    play(peers, players, lambda {
      next if left || players[0].round < INTERRUPT_ROUND
      left = true
      peers[1].client.stop
    })
    raise "bad disconnect: #{links[0].ending.to_a}" unless links[0].ending.to_a == [0, "disconnect"]
    report("OK   a disconnection gives the win to the remaining player")
    peers[0].client.stop
  end

  def self.run
    File.delete(RESULT_FILE) if File.exist?(RESULT_FILE)
    report("started")
    move_ids = GameData::Move.keys.select { |id| id.is_a?(Symbol) }
    rng = Random.new(1234)
    peers = connect(%w[Red Blue])
    forfeit_duel(peers, rng, move_ids)
    disconnect_duel(rng, move_ids)
    tally = Hash.new(0)
    deadline = now + TIME_BUDGET - 25
    seed = 0
    while now < deadline
      seed += 100
      finished_duel(peers, rng, move_ids, seed, tally, ROTATION[(seed / 100) % ROTATION.size])
    end
    report("finished duels: #{tally}")
    played_doubles = tally.keys.any? { |key| key.start_with?("doubles") }
    report(played_doubles ? "PASS" : "FAIL no doubles played")
  rescue Exception => e
    report("FAIL #{e.class}: #{e.message}\n#{(e.backtrace || []).first(8).join("\n")}")
  ensure
    exit
  end
end

class Scene_Intro
  def main
    Game.start_new
    NetworkDuelTest.run
  end
end
