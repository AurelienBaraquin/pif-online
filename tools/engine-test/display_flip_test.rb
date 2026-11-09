# Plays two duels in the real battle UI against a bot in the same process: the
# local player challenges (side 0, the regression check), then the bot
# challenges (side 1, the mirrored display). Checks the layout and the wording
# and leaves screenshots flip_side<side>_<moment>.png to be read by a person.
# Loaded after battle_determinism_test.rb, for its SilentScene.

module DisplayFlipTest
  RESULT_FILE = "test_result.txt"
  TIMEOUT_FRAMES = 10_000
  BATTLE_PRESS_INTERVAL = 8
  FIRST_MESSAGE_PRESS_FRAME = 60
  MESSAGE_PRESS_INTERVAL = 25
  COMMAND_SNAPSHOT_DELAY = 15
  ATTACK_SNAPSHOT_DELAYS = [8, 20].freeze
  PARTY_SNAPSHOT_FRAME = 38
  PARTY_CURSOR_FRAME = 44
  PARTY_FIRST_PRESS_FRAME = 52
  DUELS_EXPECTED = 2
  LOCAL_SPECIES = %w[Pikachu Squirtle].freeze
  FOE_NAME = "Bulby"
  ADDRESS = Multiplayer::Config.new("127.0.0.1", 7777)
  RULES = Multiplayer::Duel::Rules.new(2, 0, true, 60)
  BOT_APPEARANCE = {
    "skin" => 3, "clothes" => "basicnormal", "hair" => "1_afro", "hat" => nil, "hat2" => nil,
    "clothes_color" => 0, "hair_color" => 0, "hat_color" => 0, "hat2_color" => 0
  }.freeze
  BOT_POKEMON = {
    "species" => "BULBASAUR", "level" => 5, "form" => 0, "personal_id" => 1, "gender" => 0, "nature" => "HARDY",
    "ability" => "OVERGROW", "ability_index" => 0, "item" => nil, "happiness" => 70, "iv" => [1, 2, 3, 4, 5, 6],
    "iv_maxed" => [false] * 6, "ev" => [0] * 6, "moves" => [{ "id" => "TACKLE", "pp" => 35, "ppup" => 0 }],
    "name" => FOE_NAME, "shiny" => false, "head_shiny" => false, "body_shiny" => false,
    "hidden_power_type" => nil, "size_category" => nil, "pif_sprite" => nil
  }.freeze
  FakeLink = Struct.new(:side)

  module BotParty
    def self.for_rules(rules)
      Array.new(rules.party_size) { BOT_POKEMON }
    end
  end

  # Always uses its first move, and sends in the first Pokemon able to fight.
  module BotChooser
    def self.choose(_battle, _index)
      Multiplayer::DuelLink::Choice.new("move", 0)
    end

    def self.replacement(battle, index)
      battle.pbParty(index).index(&:able?)
    end
  end

  @frame = 0
  @message_frame = 0
  @message_depth = 0
  @messages = []
  @texts = Hash.new { |hash, side| hash[side] = [] }
  @failures = []
  @scheduled = []
  @taken = {}
  @completed = 0
  @bot_starts = 0
  @side = nil
  @scene = nil
  @checked_layout = false
  @party_used = false
  @party_frame = nil
  @press_right = false

  class << self
    attr_reader :side
  end

  def self.report(line)
    File.open(RESULT_FILE, "a") { |file| file.puts(line) }
  end

  def self.finish(verdict)
    report(verdict)
    exit
  end

  def self.fail_check(message)
    @failures << "side #{@side}: #{message}"
  end

  def self.begin_duel(side, scene)
    @side = side
    @scene = scene
    @checked_layout = false
  end

  def self.record_text(text)
    @texts[@side] << text if @side
  end

  def self.snapshot(moment)
    name = "flip_side#{@side}_#{moment}"
    return if @taken[name]
    @taken[name] = true
    Graphics.snap_to_bitmap.to_file("#{name}.png")
    report("snapshot #{name}")
  end

  def self.schedule(moment, delay)
    @scheduled += [[@frame + delay, moment]]
  end

  def self.run_scheduled
    due, @scheduled = @scheduled.partition { |frame, _moment| frame <= @frame }
    due.each { |_frame, moment| snapshot(moment) }
  end

  def self.on_command_menu(index)
    schedule("command", COMMAND_SNAPSHOT_DELAY)
    return if @checked_layout
    @checked_layout = true
    fail_check("command menu opened for battler #{index}") unless index == @side
    check_layout
  end

  def self.check_layout
    sprites = @scene.sprites
    own = sprites["pokemon_#{@side}"]
    foe = sprites["pokemon_#{1 - @side}"]
    own_box = sprites["dataBox_#{@side}"]
    foe_box = sprites["dataBox_#{1 - @side}"]
    fail_check("own sprite is not bottom left") unless own.y > foe.y && own.x < foe.x
    fail_check("own data box is not below the foe's") unless own_box.y > foe_box.y
    fail_check("own sprite is not a back sprite") unless own.instance_variable_get(:@back)
    fail_check("foe sprite is a back sprite") if foe.instance_variable_get(:@back)
    fail_check("own box shows #{own_box.battler.name}") unless LOCAL_SPECIES.include?(own_box.battler.name)
    fail_check("foe box shows #{foe_box.battler.name}") unless foe_box.battler.name == FOE_NAME
  end

  def self.on_animation(move_id, user_index)
    ATTACK_SNAPSHOT_DELAYS.each do |delay|
      schedule("attack_#{move_id}_by#{user_index}_plus#{delay}", delay)
    end
  end

  def self.on_party_screen(names)
    fail_check("party screen shows #{names}") unless names == LOCAL_SPECIES
  end

  # True once: makes the local player open the party screen on its first turn.
  def self.take_party_turn?
    return false if @side != Multiplayer::SideOneDisplay::SIDE || @party_used
    @party_used = true
  end

  def self.with_party_turn
    @party_frame = 0
    yield
  ensure
    @party_frame = nil
    @press_right = false
  end

  def self.press_right?
    return false unless @press_right
    @press_right = false
    true
  end

  def self.press?
    return false if @party_frame && @party_frame < PARTY_FIRST_PRESS_FRAME
    return (@frame % BATTLE_PRESS_INTERVAL).zero? if Multiplayer::DuelRunner.running && @message_depth.zero?
    return false if @message_depth.zero? || @message_frame < FIRST_MESSAGE_PRESS_FRAME
    ((@message_frame - FIRST_MESSAGE_PRESS_FRAME) % MESSAGE_PRESS_INTERVAL).zero?
  end

  def self.around_message(message)
    @messages << message
    report("message: #{message}")
    @message_depth += 1
    @message_frame = 0
    yield
  ensure
    @message_depth -= 1
  end

  def self.on_frame
    @frame += 1
    finish("FAIL timeout, completed=#{@completed}") if @frame > TIMEOUT_FRAMES
    drive_network
    run_scheduled
    advance_party_script
    @message_frame += 1 if @message_depth.positive?
  rescue SystemExit
    raise
  rescue Exception => e
    finish("FAIL #{e.class}: #{e.message}\n#{(e.backtrace || []).first(8).join("\n")}")
  end

  def self.advance_party_script
    return unless @party_frame
    @party_frame += 1
    snapshot("party") if @party_frame == PARTY_SNAPSHOT_FRAME
    @press_right = true if @party_frame == PARTY_CURSOR_FRAME
  end

  def self.drive_network
    return unless @bot
    @client.tick
    link = @duel.take_start
    start_bot_battle(link) if link
    @bot_fiber.resume if @bot_fiber&.alive?
  end

  def self.start_bot_battle(link)
    @bot_starts += 1
    scene = BattleDeterminism::SilentScene.new
    battle = Multiplayer::DuelRunner.build_battle(link, scene, BotChooser, -> { Fiber.yield })
    @bot_fiber = Fiber.new do
      begin
        battle.pbStartBattle
        battle.report_result
      rescue Exception => e
        report("bot battle error: #{e.class}: #{e.message} #{(e.backtrace || []).first(5)}")
      end
    end
  end

  def self.on_duel_finished
    @completed += 1
    @failures << "display flag left on after duel #{@completed}" if Multiplayer::SideOneDisplay.active?
  end

  def self.start_bot
    return if @bot || !Multiplayer::Runtime.feature(Multiplayer::Presence::FEATURE_NAME)
    check_flag_cleared_on_error
    @client = Multiplayer::Client.new(ADDRESS, "Bot")
    @presence = Multiplayer::Presence.new(@client)
    @duel = Multiplayer::Duel.new(@client, BotParty)
    @client.start
    @bot = true
  end

  def self.check_flag_cleared_on_error
    begin
      Multiplayer::SideOneDisplay.during(FakeLink.new(1)) { raise ArgumentError, "expected" }
    rescue ArgumentError
      @failures << "flag left on after an error" if Multiplayer::SideOneDisplay.active?
    end
  end

  def self.drive_bot
    map = $game_map.map_id
    state = Multiplayer::Presence::State.new(map, $game_player.x + 1, $game_player.y, 4, 3)
    @presence.publish(state, BOT_APPEARANCE, [map])
    invitation = @duel.take_invitation
    @duel.respond(invitation, true) if invitation
    @duel.take_notice
  end

  def self.local_challenges_bot
    return if @local_challenged || Multiplayer::DuelRunner.running
    local = Multiplayer::Runtime.feature(Multiplayer::Presence::FEATURE_NAME)
    bot = local.players_on($game_map.map_id).first
    duel = Multiplayer::Runtime.feature(Multiplayer::Duel::FEATURE_NAME)
    return unless bot && duel.idle?
    @local_challenged = duel.challenge(bot.id, RULES)
  end

  def self.bot_challenges_local
    return if @bot_challenged || @completed < 1 || @message_depth.positive?
    local = @presence.players_on($game_map.map_id).first
    return unless local && @duel.idle?
    @bot_challenged = @duel.challenge(local.id, RULES)
  end

  def self.check_texts
    [0, 1].each do |side|
      texts = @texts[side]
      report("side #{side} texts: #{texts.join(" / ")}")
      @failures << "side #{side}: no Go! for own Pokemon" unless texts.any? { |text| text =~ /Go! Pikachu/ }
      @failures << "side #{side}: foe not called opposing" unless texts.any? { |text| text =~ /The opposing #{FOE_NAME}/ }
      @failures << "side #{side}: own called opposing" if texts.any? { |text| text =~ /opposing (Pikachu|Squirtle)/ }
      @failures << "side #{side}: foe's Pokemon told Go!" if texts.any? { |text| text =~ /Go! #{FOE_NAME}/ }
      @failures << "side #{side}: no victory over the bot" unless texts.any? { |text| text =~ /You defeated .*Bot/ }
    end
  end

  def self.verify
    return if @completed < DUELS_EXPECTED || @message_depth.positive?
    raise "bot saw #{@bot_starts} duel starts" unless @bot_starts == DUELS_EXPECTED
    raise "the party screen was not reached" unless @taken["flip_side1_party"]
    check_texts
    wins = @messages.count { |message| message =~ /\AYou won the duel/ }
    @failures << "only #{wins} of #{DUELS_EXPECTED} duels were won: #{@messages.last}" unless wins == DUELS_EXPECTED
    tripped = ["runtime.tick", "duel.prompts"].select { |site| Multiplayer::Guard.tripped?(site) }
    @failures << "guards tripped: #{tripped}" unless tripped.empty?
    finish(@failures.empty? ? "PASS" : "FAIL #{@failures.join("; ")}")
  end

  def self.on_map_update
    start_bot
    return unless @bot
    drive_bot
    local_challenges_bot
    bot_challenges_local
    verify
  rescue SystemExit
    raise
  rescue Exception => e
    finish("FAIL #{e.class}: #{e.message}\n#{(e.backtrace || []).first(8).join("\n")}")
  end

  def self.open_spot
    tiles = (0...$game_map.width).to_a.product((0...$game_map.height).to_a)
    tiles.find { |x, y| area_free?(x, y) } || [$game_map.width / 2, $game_map.height / 2]
  end

  def self.area_free?(x, y)
    (-1..4).to_a.product((-3..1).to_a).all? do |dx, dy|
      [2, 4, 6, 8].all? { |dir| $game_map.passable?(x + dx, y + dy, dir) }
    end
  end

  def self.new_pokemon(species, move)
    pokemon = Pokemon.new(species, 20)
    pokemon.moves.clear
    pokemon.learn_move(move)
    pokemon
  end

  module SceneProbe
    def pbStartBattle(battle)
      DisplayFlipTest.begin_duel(@link.side, self)
      super
    end

    def pbSendOutBattlers(send_outs, start_battle = false)
      super
      DisplayFlipTest.snapshot("sendout")
    end

    def pbCommandMenu(index, first_action)
      DisplayFlipTest.on_command_menu(index)
      super
    end

    def pbAnimation(move_id, user, targets, hit_number = 0)
      DisplayFlipTest.on_animation(move_id, user.index)
      super
    end

    def pbPartyScreen(index, can_cancel = false, &block)
      DisplayFlipTest.on_party_screen(@battle.pbPlayerDisplayParty(index).map(&:name))
      super
    end

    def pbDisplayMessage(message, brief = false)
      DisplayFlipTest.record_text(message)
      super
    end

    def pbDisplayPausedMessage(message)
      DisplayFlipTest.record_text(message)
      super
    end

    def pbEndBattle(result)
      DisplayFlipTest.snapshot("end")
      super
    end
  end

  module ScriptedChooser
    def choose(battle, index)
      return super unless DisplayFlipTest.take_party_turn?
      switched = DisplayFlipTest.with_party_turn { battle.pbPartyMenu(index) }
      switched ? take_choice(battle, index) : super
    end
  end

  module CountedRunner
    def run(link)
      super
      DisplayFlipTest.on_duel_finished
    end
  end
end

PokeBattle_Scene.prepend(DisplayFlipTest::SceneProbe)
Multiplayer::LocalChooser.singleton_class.prepend(DisplayFlipTest::ScriptedChooser)
Multiplayer::DuelRunner.singleton_class.prepend(DisplayFlipTest::CountedRunner)

alias display_flip_test_original_message pbMessage

def pbMessage(message, commands = nil, *args, &block)
  DisplayFlipTest.around_message(message) do
    display_flip_test_original_message(message, commands, *args, &block)
  end
end

class << Graphics
  alias_method :display_flip_test_original_update, :update

  def update
    display_flip_test_original_update
    DisplayFlipTest.on_frame
  end
end

class << Input
  alias_method :display_flip_test_original_trigger, :trigger?
  alias_method :display_flip_test_original_repeat, :repeat?

  def trigger?(button)
    return true if button == Input::USE && DisplayFlipTest.press?
    display_flip_test_original_trigger(button)
  end

  def repeat?(button)
    return true if button == Input::RIGHT && DisplayFlipTest.press_right?
    display_flip_test_original_repeat(button)
  end
end

class Scene_Intro
  OUTDOOR_MAP_NAME = /Littleroot|Oldale|Petalburg/i

  def main
    Game.start_new
    map_id, = load_data("Data/MapInfos.rxdata").find { |_id, info| info.name =~ OUTDOOR_MAP_NAME }
    $MapFactory.setup(map_id)
    pbChangePlayer(0)
    $game_player.moveto(*DisplayFlipTest.open_spot)
    $game_player.refresh
    $Trainer.party = [DisplayFlipTest.new_pokemon(:PIKACHU, :THUNDERBOLT), DisplayFlipTest.new_pokemon(:SQUIRTLE, :WATERGUN)]
  end
end

File.delete(DisplayFlipTest::RESULT_FILE) if File.exist?(DisplayFlipTest::RESULT_FILE)
Events.onMapUpdate += proc { |_sender, _e| DisplayFlipTest.on_map_update }
