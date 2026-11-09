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
  INTRO_SNAPSHOT_DELAY = 6
  LOCAL_OUTFIT = { :@skin_tone => 5, :@clothes => "red", :@hair => "2_bob", :@hat => "ash" }.freeze
  PIXEL_STEP = 3
  HOSTILE_APPEARANCE = {
    "skin" => 99, "clothes" => "../../nope", "hair" => "no_such_hair", "hat" => "a..b", "hat2" => "a/b",
    "clothes_color" => "red", "hair_color" => 1e12, "hat_color" => nil, "hat2_color" => -1e12
  }.freeze
  ATTACK_SNAPSHOT_DELAYS = [8, 20].freeze
  PARTY_SNAPSHOT_FRAME = 38
  PARTY_CURSOR_FRAME = 44
  PARTY_FIRST_PRESS_FRAME = 52
  # Who challenges, by duel: the local player is side 0, the bot makes it side 1.
  DUELS = [
    [:local, Multiplayer::Duel::Rules.new(2, 0, true, 60)],
    [:bot, Multiplayer::Duel::Rules.new(2, 0, true, 60)],
    [:local, Multiplayer::Duel::Rules.new(2, 0, true, 60, [], "doubles")],
    [:bot, Multiplayer::Duel::Rules.new(2, 0, true, 60, ["sleep"], "doubles")]
  ].freeze
  DUELS_EXPECTED = DUELS.size
  TARGET_SNAPSHOT_DELAY = 4
  LOCAL_SPECIES = %w[Pikachu Squirtle].freeze
  FOE_NAME = "Bulby"
  ADDRESS = Multiplayer::Config.new("127.0.0.1", 7777)
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

    def self.appearance
      BOT_APPEARANCE
    end
  end

  # Always uses its first move, and sends in the first Pokemon able to fight.
  module BotChooser
    def self.choose(_battle, indices)
      indices.to_h { |index| [index, Multiplayer::DuelLink::Choice.new("move", 0)] }
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
  @challenges_sent = 0
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

  def self.begin_duel(side, scene, format)
    @side = side
    @format = format
    @scene = scene
    @checked_layout = false
  end

  def self.record_text(text)
    @texts[@side] << text if @side
    schedule("intro", INTRO_SNAPSHOT_DELAY) if text =~ /challenged by/
  end

  def self.snapshot(moment)
    name = "flip_#{@format == "doubles" ? "doubles_" : ""}side#{@side}_#{moment}"
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
    check_double_layout(sprites) if @format == "doubles"
    fail_check("own sprite is not bottom left") unless own.y > foe.y && own.x < foe.x
    fail_check("own data box is not below the foe's") unless own_box.y > foe_box.y
    fail_check("own sprite is not a back sprite") unless own.instance_variable_get(:@back)
    fail_check("foe sprite is a back sprite") if foe.instance_variable_get(:@back)
    fail_check("own box shows #{own_box.battler.name}") unless LOCAL_SPECIES.include?(own_box.battler.name)
    fail_check("foe box shows #{foe_box.battler.name}") unless foe_box.battler.name == FOE_NAME
    check_trainer("player_1", Multiplayer::LocalPlayer.appearance)
    check_trainer("trainer_1", BOT_APPEARANCE)
    check_fallbacks
  end

  # Both of the viewer's battlers are near, its first on the left.
  def self.check_double_layout(sprites)
    own = [sprites["pokemon_#{@side}"], sprites["pokemon_#{@side + 2}"]]
    foe = [sprites["pokemon_#{1 - @side}"], sprites["pokemon_#{3 - @side}"]]
    fail_check("own battlers are not on the near side") unless own.all? { |sprite| sprite.y > foe.map(&:y).max }
    fail_check("own second is not right of own first") unless own[1].x > own[0].x
    fail_check("foe second is not left of foe first") unless foe[1].x < foe[0].x
    fail_check("own boxes are not below the foe's") unless sprites["dataBox_#{@side}"].y > sprites["dataBox_#{1 - @side}"].y
    fail_check("own second box is not lowest") unless sprites["dataBox_#{@side + 2}"].y > sprites["dataBox_#{@side}"].y
  end

  # The sprite must show exactly what the duelist's own appearance generates.
  def self.check_trainer(name, wire)
    expected = generate_front_trainer_sprite_bitmap_from_appearance(Multiplayer::DuelLook.from_wire(wire), false).bitmap
    actual = @scene.sprites[name].bitmap
    fail_check("#{name} does not show its duelist") unless same_pixels?(actual, expected)
    foe = @scene.sprites["trainer_1"]
    fail_check("trainer_1 origin #{foe.ox},#{foe.oy}") unless foe.ox == foe.bitmap.width / 2 && foe.oy == foe.bitmap.height
  end

  def self.same_pixels?(first, second)
    return false unless first.width == second.width && first.height == second.height
    (0...first.width).step(PIXEL_STEP).to_a.product((0...first.height).step(PIXEL_STEP).to_a).all? do |x, y|
      first.get_pixel(x, y).to_s == second.get_pixel(x, y).to_s
    end
  end

  # Hostile values are drawn with the game's fallbacks, and a duelist that
  # cannot be drawn at all keeps the sprite the engine made.
  def self.check_fallbacks
    look = Multiplayer::DuelLook.from_wire(HOSTILE_APPEARANCE)
    fail_check("traversal accepted") unless look.clothes.nil? && look.hat.nil? && look.hat2.nil?
    fail_check("colors not clamped") unless look.hair_color == 1_000_000 && look.hat2_color == -1_000_000 && look.clothes_color.zero?
    fail_check("non-hash appearance accepted") if Multiplayer::DuelLook.from_wire("nope")
    generate_front_trainer_sprite_bitmap_from_appearance(look, false)
    sprite = @scene.sprites["trainer_1"]
    before = sprite.bitmap
    @scene.send(:dress, sprite, 9)
    fail_check("unknown side replaced the sprite") unless sprite.bitmap.equal?(before)
  end

  # The default target of a local move is a foe, however the side is mirrored.
  def self.on_taken_choice(choice)
    return unless choice.target
    fail_check("default target #{choice.target} is not a foe") unless choice.target & 1 != @side
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
    dress_local_player
    @client = Multiplayer::Client.new(ADDRESS, "Bot")
    @presence = Multiplayer::Presence.new(@client)
    @duel = Multiplayer::Duel.new(@client, BotParty)
    @client.start
    @bot = true
  end

  # A new game has no outfit, which would hide what the near sprite shows. The
  # game's setters redraw the player, re-entering this test from Graphics.update.
  def self.dress_local_player
    LOCAL_OUTFIT.each { |name, value| $Trainer.instance_variable_set(name, value) }
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

  def self.issue_next_challenge
    return if @challenges_sent != @completed || @completed >= DUELS.size
    return if Multiplayer::DuelRunner.running || @message_depth.positive?
    challenger, rules = DUELS[@completed]
    @challenges_sent += 1 if challenger == :local ? local_challenges_bot(rules) : bot_challenges_local(rules)
  end

  def self.local_challenges_bot(rules)
    local = Multiplayer::Runtime.feature(Multiplayer::Presence::FEATURE_NAME)
    bot = local.players_on($game_map.map_id).first
    duel = Multiplayer::Runtime.feature(Multiplayer::Duel::FEATURE_NAME)
    bot && duel.idle? && duel.challenge(bot.id, rules)
  end

  def self.bot_challenges_local(rules)
    local = @presence.players_on($game_map.map_id).first
    local && @duel.idle? && @duel.challenge(local.id, rules)
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
      @failures << "side #{side}: not challenged by the bot" unless texts.any? { |text| text =~ /challenged by .*Bot/ }
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
    issue_next_challenge
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
      DisplayFlipTest.begin_duel(@link.side, self, @link.rules["format"])
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

    def pbChooseTarget(idx_battler, target_data, visible_sprites = nil)
      DisplayFlipTest.schedule("target", TARGET_SNAPSHOT_DELAY)
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
    def choose(battle, indices)
      return super unless DisplayFlipTest.take_party_turn?
      index = indices.first
      switched = DisplayFlipTest.with_party_turn { battle.pbPartyMenu(index) }
      switched ? { index => take_choice(battle, index) } : super
    end

    def take_choice(battle, index)
      super.tap { |choice| DisplayFlipTest.on_taken_choice(choice) }
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
