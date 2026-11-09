# Starts the real game on a new save, without its title screen, and has a second
# client walk next to the player. Writes test_result.txt and test_screen.png.

module GameTest
  RESULT_FILE = "test_result.txt"
  SCREENSHOT = "test_screen.png"
  TIMEOUT_FRAMES = 1200
  SETTLE_FRAMES = 120
  ADDRESS = Multiplayer::Config.new("127.0.0.1", 7777)
  BOT_APPEARANCE = {
    "skin" => 3, "clothes" => "basicnormal", "hair" => "1_afro", "hat" => nil, "hat2" => nil,
    "clothes_color" => 0, "hair_color" => 0, "hat_color" => 0, "hat2_color" => 0
  }.freeze

  @frame = 0
  @bot = nil
  @walked_frames = 0

  def self.report(line)
    File.open(RESULT_FILE, "a") { |file| file.puts(line) }
  end

  def self.finish(verdict)
    report(verdict)
    exit
  end

  def self.remote_entries
    sprites = $scene.spriteset.usersprites.find { |entry| entry.is_a?(Multiplayer::RemotePlayerSprites) }
    sprites ? sprites.instance_variable_get(:@entries) : {}
  end

  def self.start_bot
    return if @bot || !Multiplayer::Runtime.feature(Multiplayer::Presence::FEATURE_NAME)
    @client = Multiplayer::Client.new(ADDRESS, "Bot")
    @bot = Multiplayer::Presence.new(@client)
    @client.start
    report("OK   overlay session started for #{$Trainer.name.inspect}")
  end

  def self.publish_bot
    map = $game_map.map_id
    offset = (@frame / 40).even? ? 2 : 3
    state = Multiplayer::Presence::State.new(map, $game_player.x + offset, $game_player.y, 6, 3)
    @bot.publish(state, BOT_APPEARANCE, [map])
  end

  def self.verify_rendering
    entries = remote_entries
    return if entries.empty?
    @walked_frames += 1
    return if @walked_frames < SETTLE_FRAMES
    sprite = entries.values.first.sprite
    raise "remote sprite has no bitmap" unless sprite.bitmap && !sprite.bitmap.disposed?
    report("OK   remote sprite #{sprite.src_rect.width}x#{sprite.src_rect.height} at #{sprite.x},#{sprite.y}")
    raise "bot does not see local player" if @bot.players_on($game_map.map_id).empty?
    report("OK   second client sees the local player")
    Graphics.snap_to_bitmap.to_file(SCREENSHOT)
    guards = ["runtime.tick", "presence.publish", Multiplayer::RemotePlayerSprites::GUARD_SITE]
    tripped = guards.select { |site| Multiplayer::Guard.tripped?(site) }
    raise "guards tripped: #{tripped}" unless tripped.empty?
    finish("PASS")
  end

  def self.update
    @frame += 1
    finish("FAIL timeout, entries=#{remote_entries.size}, running=#{Multiplayer::Runtime.running?}") if @frame > TIMEOUT_FRAMES
    start_bot
    return unless @bot
    @client.tick
    publish_bot
    verify_rendering
  rescue SystemExit
    raise
  rescue Exception => e
    finish("FAIL #{e.class}: #{e.message}\n#{(e.backtrace || []).first(8).join("\n")}")
  end
end

class Scene_Intro
  OUTDOOR_MAP_NAME = /Littleroot|Oldale|Petalburg/i

  def main
    Game.start_new
    map_id, = load_data("Data/MapInfos.rxdata").find { |_id, info| info.name =~ OUTDOOR_MAP_NAME }
    $MapFactory.setup(map_id)
    pbChangePlayer(0)
    $game_player.moveto(*open_spot)
    $game_player.refresh
  end

  # Finds a tile with enough free ground around it for both characters, so that
  # no building or tree can hide part of a sprite.
  def open_spot
    tiles = (0...$game_map.width).to_a.product((0...$game_map.height).to_a)
    tiles.find { |x, y| area_free?(x, y) } || [$game_map.width / 2, $game_map.height / 2]
  end

  def area_free?(x, y)
    (-1..4).to_a.product((-3..1).to_a).all? do |dx, dy|
      [2, 4, 6, 8].all? { |dir| $game_map.passable?(x + dx, y + dy, dir) }
    end
  end
end

File.delete(GameTest::RESULT_FILE) if File.exist?(GameTest::RESULT_FILE)
Events.onMapUpdate += proc { |_sender, _e| GameTest.update }
