# Checks each duel rule in the real game: team legality, the effect of every
# engine clause on the simulation, the cancellation of illegal duels through
# the real server, and the rules menus. Loaded after network_duel_test.rb.

module RulesDuelTest
  RESULT_FILE = "test_result.txt"
  MENU_SNAPSHOT_FRAME = 50
  MENU_PRESS_FRAME = 60
  Clauses = Multiplayer::DuelClauses
  Codec = Multiplayer::PartyCodec

  class SilentClient
    def deliver(_type, _data); end
  end

  module IdleChooser
    def self.choose(_battle, indices)
      indices.to_h { |index| [index, Multiplayer::DuelLink::Choice.new("move", 0)] }
    end

    def self.replacement(_battle, _index)
      0
    end
  end

  class << self
    attr_accessor :menu_frame, :menu_shot
  end

  def self.report(line)
    File.open(RESULT_FILE, "a") { |file| file.puts(line) }
  end

  def self.check(description, passed)
    raise "failed: #{description}" unless passed
    report("OK   #{description}")
  end

  def self.pokemon(species, item: nil, ability: nil, moves: [:TACKLE])
    built = Pokemon.new(species, 20)
    built.item = item
    built.ability = ability if ability
    built.moves.clear
    moves.each { |move| built.learn_move(move) }
    built
  end

  def self.violation(party, clause)
    found = Clauses.violation(Codec.encode(party), [clause])
    found&.id
  end

  def self.legality
    species = [pokemon(:PIKACHU), pokemon(:PIKACHU)]
    check("species clause rejects a duplicate", violation(species, "species") == "species")
    check("species clause accepts swapped head and body", violation([pokemon(:B25H26), pokemon(:B26H25)], "species").nil?)
    check("species clause rejects the same fusion twice", violation([pokemon(:B25H26), pokemon(:B25H26)], "species") == "species")
    check("item clause rejects a duplicate", violation([pokemon(:PIKACHU, item: :LEFTOVERS), pokemon(:EEVEE, item: :LEFTOVERS)], "item") == "item")
    check("item clause accepts empty hands", violation([pokemon(:PIKACHU), pokemon(:EEVEE)], "item").nil?)
    check("moody clause rejects Moody", violation([pokemon(:PIKACHU, ability: :MOODY)], "moody") == "moody")
    check("moody clause accepts others", violation([pokemon(:PIKACHU)], "moody").nil?)
    check("legendary ban rejects Mewtwo", violation([pokemon(:MEWTWO)], "no_legendary") == "no_legendary")
    check("legendary ban rejects a fusion with Mewtwo", violation([pokemon(:B150H25)], "no_legendary") == "no_legendary")
    check("legendary ban accepts Pikachu", violation([pokemon(:PIKACHU)], "no_legendary").nil?)
    check("fusion ban rejects a fusion", violation([pokemon(:B25H26)], "no_fusion") == "no_fusion")
    check("fusion ban accepts Pikachu", violation([pokemon(:PIKACHU)], "no_fusion").nil?)
    check("an unreadable team is refused", Clauses.violation([{ "species" => "?" }], []) == Clauses::UNREADABLE_TEAM)
  end

  def self.local_team
    rules = Multiplayer::Duel::Rules.new(2, 0, true, 60, ["species"])
    $Trainer.party = [pokemon(:PIKACHU), pokemon(:PIKACHU)]
    check("the local team is reported as illegal", Multiplayer::DuelParty.violation(rules)&.id == "species")
    check("an illegal local team is not sent", Multiplayer::DuelParty.for_rules(rules).nil?)
    $Trainer.party = [pokemon(:PIKACHU), pokemon(:EEVEE)]
    check("a legal local team is sent", Multiplayer::DuelParty.for_rules(rules)&.size == 2)
    rules.party_size = 3
    check("a team that shrank is not sent", Multiplayer::DuelParty.for_rules(rules).nil?)
  end

  # A battle stopped at its first command phase, with battlers on the field.
  def self.battle(clauses, moves, party_size, format = "singles")
    party = Codec.encode(Array.new(party_size) { |slot| pokemon(slot.zero? ? :PIKACHU : :EEVEE, moves: moves) })
    link = Multiplayer::DuelLink.new(SilentClient.new, {
      "seed" => 1, "side" => 0, "rules" => { "turn_seconds" => 60, "clauses" => clauses, "format" => format },
      "players" => [{ "name" => "A" }, { "name" => "B" }], "parties" => [party, party]
    })
    built = Multiplayer::DuelRunner.build_battle(link, BattleDeterminism::SilentScene.new, IdleChooser, -> { Fiber.yield })
    Fiber.new { built.pbStartBattle }.resume
    built
  end

  def self.move_of(built, id)
    PokeBattle_Move.from_pokemon_move(built, Pokemon::Move.new(id))
  end

  # Runs a probe with the clause on and off: only the clause may change it.
  def self.clause_effect(description, clause, moves, party_size)
    on = yield battle([clause], moves, party_size)
    off = yield battle([], moves, party_size)
    check("#{description}: blocked with the clause, allowed without", on && !off)
  end

  def self.engine_clauses
    clause_effect("sleep clause", "sleep", [:TACKLE], 2) do |built|
      built.pbParty(0)[1].status = :SLEEP
      !built.battlers[0].pbCanSleep?(built.battlers[1], false)
    end
    clause_effect("freeze clause", "freeze", [:TACKLE], 2) do |built|
      built.pbParty(0)[1].status = :FROZEN
      !built.battlers[0].pbCanFreeze?(built.battlers[1], false)
    end
    { "DOUBLETEAM" => :DOUBLETEAM, "MINIMIZE" => :MINIMIZE }.each do |name, id|
      clause_effect("evasion clause on #{name}", "evasion", [:TACKLE], 1) do |built|
        move_of(built, id).pbMoveFailed?(built.battlers[0], [built.battlers[1]])
      end
    end
    { "ohko" => :FISSURE, "skill_swap" => :SKILLSWAP, "sonic_boom" => :SONICBOOM, "perish" => :PERISHSONG }.each do |clause, id|
      clause_effect("#{clause} clause on #{id}", clause, [:TACKLE], 1) do |built|
        built.battlers[1].ability_id = :INTIMIDATE # Skill Swap fails between equal abilities.
        move_of(built, id).pbFailsAgainstTarget?(built.battlers[0], built.battlers[1])
      end
    end
    rules = battle(%w[sleep ohko species], [:TACKLE], 1).rules
    check("clauses set exactly their engine rules", rules["sleepclause"] && rules["ohkoclause"] && !rules["speciesclause"] && !rules["freezeclause"])
  end

  def self.wire_party(*species)
    Codec.encode(species.map { |id| pokemon(id) })
  end

  def self.start(peers, rules)
    red, blue = peers
    red.duel.challenge(blue.client.player_id, rules)
    invitation = NetworkDuelTest.wait_until(peers, "invitation") { blue.duel.take_invitation }
    blue.duel.respond(invitation, true)
    invitation
  end

  def self.illegal_opponent(peers)
    rules = Multiplayer::Duel::Rules.new(1, 0, true, 60, ["no_legendary"])
    peers[0].source.party = wire_party(:PIKACHU)
    peers[1].source.party = wire_party(:MEWTWO)
    invitation = start(peers, rules)
    check("clauses reach the invited player", invitation.rules.clauses == ["no_legendary"])
    links = peers.map { |peer| NetworkDuelTest.wait_until(peers, "start") { peer.duel.take_start } }
    check("the server lets a legendary through", links[0].rules["clauses"] == ["no_legendary"])
    check("the receiver sees the opponent's illegal team", Clauses.violation(links[0].parties[1], links[0].rules["clauses"])&.id == "no_legendary")
    links[0].reject
    NetworkDuelTest.wait_until(peers, "ending") { links.all?(&:ending) }
    check("the duel ends cleanly without a winner", links.all? { |link| link.ending.to_a == [nil, "illegal_party"] })
  end

  def self.team_changed_before_sending(peers)
    rules = Multiplayer::Duel::Rules.new(1, 0, true, 60, ["species"])
    peers[0].source.party = nil
    peers[1].source.party = wire_party(:PIKACHU)
    start(peers, rules)
    notices = peers.map { |peer| NetworkDuelTest.wait_until(peers, "notice") { peer.duel.take_notice } }
    check("a team that became illegal cancels the duel", notices.map(&:reason).uniq == ["illegal_party"])
    check("the connection survives", peers.all? { |peer| peer.client.ready? })
  end

  def self.network
    peers = NetworkDuelTest.connect(%w[Red Blue])
    illegal_opponent(peers)
    team_changed_before_sending(peers)
  end

  def self.format_setting
    menu = Multiplayer::RulesMenu
    rules = Multiplayer::Duel::Rules.new(1, 0, true, 60)
    doubles = menu.next_format(rules, 6)
    check("doubles raises the team to two", doubles.format == "doubles" && doubles.party_size == 2)
    check("doubles is not offered to a single Pokémon", menu.next_format(rules, 1).format == "singles")
    check("the doubles team size wraps to two", menu.next_party_size(menu.with(doubles, :party_size, 6), 6).party_size == 2)
    check("the singles team size wraps to one", menu.next_party_size(menu.with(rules, :party_size, 6), 6).party_size == 1)
    report("OK   summary: #{menu.summary(doubles).first}")
    check("the format reaches the wire", doubles.to_wire["format"] == "doubles")
    built = battle([], [:TACKLE], 2, "doubles")
    check("the battle is a double battle", built.pbSideSize(0) == 2 && built.battlers.compact.size == 4)
  end

  def self.summary
    rules = Multiplayer::Duel::Rules.new(3, 50, false, 60, Clauses::ALL.map(&:id))
    lines = Multiplayer::RulesMenu.summary(rules)
    report("summary: #{lines.join(" / ")}")
    check("the summary is split in short messages", lines.size == 4 && lines.all? { |line| line.length < 80 })
  end

  # Opens a menu, takes a screenshot, then backs out with the cancel button.
  def self.capture_menu(name)
    @menu_name = name
    @menu_frame = 0
    @menu_open = true
    result = yield
    @menu_open = false
    result
  end

  def self.on_frame
    return unless @menu_open
    @menu_frame += 1
    Graphics.snap_to_bitmap.to_file("test_rules_#{@menu_name}.png") if @menu_frame == MENU_SNAPSHOT_FRAME
  end

  def self.press_back?
    @menu_open && @menu_frame >= MENU_PRESS_FRAME
  end

  def self.menus
    menu = Multiplayer::RulesMenu
    check("backing out cancels the challenge", capture_menu("main") { menu.choose(6) }.nil?)
    rules = Multiplayer::Duel::Rules.new(3, 0, true, 60, [])
    check("the clause page returns the rules", capture_menu("clauses") { menu.edit_clauses(rules) }.clauses == [])
    pages = Clauses::ALL.each_slice(menu::CLAUSES_PER_PAGE).count
    check("clauses are paginated", pages > 1)
    check("toggling adds then removes a clause", menu.toggled(menu.toggled(rules, "sleep"), "sleep").clauses.empty? && menu.toggled(rules, "sleep").clauses == ["sleep"])
  end

  def self.run
    File.delete(RESULT_FILE) if File.exist?(RESULT_FILE)
    report("started")
    legality
    local_team
    engine_clauses
    summary
    format_setting
    network
    menus
    report("PASS")
  rescue Exception => e
    report("FAIL #{e.class}: #{e.message}\n#{(e.backtrace || []).first(8).join("\n")}")
  ensure
    exit
  end
end

class << Graphics
  alias_method :rules_test_original_update, :update

  def update
    rules_test_original_update
    RulesDuelTest.on_frame
  end
end

class << Input
  alias_method :rules_test_original_trigger, :trigger?

  def trigger?(button)
    return true if button == Input::BACK && RulesDuelTest.press_back?
    rules_test_original_trigger(button)
  end
end

# The menus need a live map scene, so the test starts from the first map update.
class Scene_Intro
  OUTDOOR_MAP_NAME = /Littleroot|Oldale|Petalburg/i

  def main
    Game.start_new
    map_id, = load_data("Data/MapInfos.rxdata").find { |_id, info| info.name =~ OUTDOOR_MAP_NAME }
    $MapFactory.setup(map_id)
    pbChangePlayer(0)
    $game_player.refresh
    $Trainer.party = [Pokemon.new(:PIKACHU, 20)]
  end
end

RulesDuelTest.instance_variable_set(:@started, false)

def RulesDuelTest.start_once
  return if @started
  @started = true
  run
end

Events.onMapUpdate += proc { |_sender, _e| RulesDuelTest.start_once }
