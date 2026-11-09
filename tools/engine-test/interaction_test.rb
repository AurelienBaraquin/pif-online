# Drives the interaction window and the battle UI in the real game with scripted
# key presses: the local player challenges a bot, then the bot challenges the
# local player. The bot plays its own NetworkBattle in a Fiber. Loaded after
# battle_determinism_test.rb. Writes test_result.txt and screenshots.

module InteractionTest
  RESULT_FILE = "test_result.txt"
  TIMEOUT_FRAMES = 6500
  BATTLE_PRESS_INTERVAL = 8
  BATTLE_SNAPSHOT_INTERVAL = 220
  MAX_BATTLE_SNAPSHOTS = 8
  SNAPSHOT_FRAME = 55
  FIRST_PRESS_FRAME = 60
  PRESS_INTERVAL = 25
  DUELS_EXPECTED = 2
  ADDRESS = Multiplayer::Config.new("127.0.0.1", 7777)
  RULES = Multiplayer::Duel::Rules.new(1, 0, true, 60)
  BOT_APPEARANCE = {
    "skin" => 3, "clothes" => "basicnormal", "hair" => "1_afro", "hat" => nil, "hat2" => nil,
    "clothes_color" => 0, "hair_color" => 0, "hat_color" => 0, "hat2_color" => 0
  }.freeze
  BOT_POKEMON = {
    "species" => "BULBASAUR", "level" => 5, "form" => 0, "personal_id" => 1, "gender" => 0, "nature" => "HARDY",
    "ability" => "OVERGROW", "ability_index" => 0, "item" => nil, "happiness" => 70, "iv" => [1, 2, 3, 4, 5, 6],
    "iv_maxed" => [false] * 6, "ev" => [0] * 6, "moves" => [{ "id" => "TACKLE", "pp" => 35, "ppup" => 0 }],
    "name" => "Bulby", "shiny" => false, "head_shiny" => false, "body_shiny" => false,
    "hidden_power_type" => nil, "size_category" => nil, "pif_sprite" => nil
  }.freeze

  module BotParty
    def self.for_rules(rules)
      Array.new(rules.party_size) { BOT_POKEMON }
    end

    def self.appearance
      {}
    end
  end

  # Always uses its first move.
  module BotChooser
    def self.choose(_battle, indices)
      indices.to_h { |index| [index, Multiplayer::DuelLink::Choice.new("move", 0)] }
    end

    def self.replacement(_battle, _index)
      0
    end
  end

  @frame = 0
  @battle_snapshots = 0
  @message_frame = 0
  @message_depth = 0
  @snapshots = 0
  @messages = []
  @opened_menu = false
  @bot_challenged = false
  @bot_starts = 0

  def self.report(line)
    File.open(RESULT_FILE, "a") { |file| file.puts(line) }
  end

  def self.finish(verdict)
    report(verdict)
    exit
  end

  def self.press?
    return (@frame % BATTLE_PRESS_INTERVAL).zero? if Multiplayer::DuelRunner.running && @message_depth.zero?
    return false if @message_depth.zero? || @message_frame < FIRST_PRESS_FRAME
    ((@message_frame - FIRST_PRESS_FRAME) % PRESS_INTERVAL).zero?
  end

  def self.around_message(message, commands)
    @messages << [message, commands]
    report("message: #{message} #{commands&.join(" | ")}")
    @message_depth += 1
    @message_frame = 0
    @snapshot_taken = false
    yield
  ensure
    @message_depth -= 1
  end

  def self.on_frame
    @frame += 1
    finish("FAIL timeout, messages=#{@messages.size}") if @frame > TIMEOUT_FRAMES
    drive_network
    snapshot_battle
    return unless @message_depth.positive?
    @message_frame += 1
    snapshot if @message_frame == SNAPSHOT_FRAME && !@snapshot_taken
  end

  def self.snapshot_battle
    return unless Multiplayer::DuelRunner.running && (@frame % BATTLE_SNAPSHOT_INTERVAL).zero?
    return if @battle_snapshots >= MAX_BATTLE_SNAPSHOTS
    @battle_snapshots += 1
    Graphics.snap_to_bitmap.to_file("test_battle_#{@battle_snapshots}.png")
  end

  # Runs from Graphics.update so that the bot keeps playing during the battle.
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

  def self.snapshot
    @snapshot_taken = true
    @snapshots += 1
    Graphics.snap_to_bitmap.to_file("test_menu_#{@snapshots}.png")
  end

  def self.start_bot
    return if @bot || !Multiplayer::Runtime.feature(Multiplayer::Presence::FEATURE_NAME)
    @client = Multiplayer::Client.new(ADDRESS, "Bot")
    @presence = Multiplayer::Presence.new(@client)
    @duel = Multiplayer::Duel.new(@client, BotParty)
    @client.start
    @bot = true
  end

  def self.drive_bot
    map = $game_map.map_id
    state = Multiplayer::Presence::State.new(map, $game_player.x + 1, $game_player.y, 4, 3)
    @presence.publish(state, BOT_APPEARANCE, [map])
    invitation = @duel.take_invitation
    @duel.respond(invitation, true) if invitation
    @duel.take_notice
  end

  def self.remote_visible?
    sprites = $scene.spriteset.usersprites.find { |entry| entry.is_a?(Multiplayer::RemotePlayerSprites) }
    sprites && !sprites.instance_variable_get(:@entries).empty?
  end

  def self.open_menu
    return if @opened_menu || !remote_visible? || $game_player.moving?
    @opened_menu = true
    $game_player.turn_right
    $PokemonTemp.hiddenMoveEventCalling = true
  end

  def self.finished_duels
    @messages.count { |message, _commands| message =~ /\AYou won|\AYou lost|without a winner/ }
  end

  def self.bot_challenges_player
    return if @bot_challenged || finished_duels < 1 || @message_depth.positive?
    local = @presence.players_on($game_map.map_id).first
    return unless local && @duel.idle?
    @bot_challenged = @duel.challenge(local.id, RULES)
  end

  def self.verify
    return if finished_duels < DUELS_EXPECTED || @message_depth.positive?
    tripped = ["runtime.tick", "presence.publish", "interaction.menu", "duel.prompts"].select { |site| Multiplayer::Guard.tripped?(site) }
    raise "guards tripped: #{tripped}" unless tripped.empty?
    raise "bot saw #{@bot_starts} duel starts" unless @bot_starts == DUELS_EXPECTED
    finish("PASS")
  end

  def self.on_map_update
    start_bot
    return unless @bot
    drive_bot
    open_menu
    bot_challenges_player
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
end

alias interaction_test_original_message pbMessage

def pbMessage(message, commands = nil, *args, &block)
  InteractionTest.around_message(message, commands) do
    interaction_test_original_message(message, commands, *args, &block)
  end
end

class << Graphics
  alias_method :interaction_test_original_update, :update

  def update
    interaction_test_original_update
    InteractionTest.on_frame
  end
end

class << Input
  alias_method :interaction_test_original_trigger, :trigger?

  def trigger?(button)
    return true if button == Input::USE && InteractionTest.press?
    interaction_test_original_trigger(button)
  end
end

class Scene_Intro
  OUTDOOR_MAP_NAME = /Littleroot|Oldale|Petalburg/i

  def main
    Game.start_new
    map_id, = load_data("Data/MapInfos.rxdata").find { |_id, info| info.name =~ OUTDOOR_MAP_NAME }
    $MapFactory.setup(map_id)
    pbChangePlayer(0)
    $game_player.moveto(*InteractionTest.open_spot)
    $game_player.refresh
    pikachu = Pokemon.new(:PIKACHU, 20)
    pikachu.moves.clear
    pikachu.learn_move(:THUNDERBOLT)
    $Trainer.party = [pikachu]
  end
end

File.delete(InteractionTest::RESULT_FILE) if File.exist?(InteractionTest::RESULT_FILE)
Events.onMapUpdate += proc { |_sender, _e| InteractionTest.on_map_update }
