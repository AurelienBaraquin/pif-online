# Two real game processes load real saves, meet on the same map through the real
# server and check, each from its own side, that it sees the other player and
# that its own team can be encoded for a duel. Each process takes its role from
# PIF_TEST_ROLE and loads saves/<role>.rxdata when the stage has one.
# Writes test_result_<role>.txt and test_presence_<role>.png.

module PresenceTest
  ROLE = ENV.fetch("PIF_TEST_ROLE")
  RESULT_FILE = "test_result_#{ROLE}.txt"
  SCREENSHOT = "test_presence_#{ROLE}.png"
  SAVE_FILE = "saves/#{ROLE}.rxdata"
  # Where the two real players stood when one could not see the other.
  MEETING_MAP = 9
  SPOTS = { "red" => [16, 13, 4], "blue" => [17, 14, 8] }.freeze
  TIMEOUT_FRAMES = 2400
  SETTLE_FRAMES = 90
  # Keeps this player on the server long enough for the other side to check.
  LINGER_FRAMES = 600

  @frame = 0
  @seen_frames = 0
  @passed_at = nil

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

  def self.diagnosis
    presence = Multiplayer::Runtime.feature(Multiplayer::Presence::FEATURE_NAME)
    known = presence ? presence.players_on($game_map.map_id).map { |player| [player.name, player.state.to_a] } : []
    tripped = Multiplayer::Guard.instance_variable_get(:@tripped).keys
    "status=#{Multiplayer::Runtime.status} map=#{$game_map.map_id} known=#{known} sprites=#{remote_entries.size} tripped=#{tripped}"
  end

  def self.visible_sprite
    entry = remote_entries.values.first
    return nil unless entry
    sprite = entry.sprite
    on_screen = sprite.x.between?(0, Graphics.width) && sprite.y.between?(0, Graphics.height)
    sprite.bitmap && !sprite.bitmap.disposed? && sprite.visible && sprite.opacity.positive? && on_screen ? sprite : nil
  end

  def self.check_sight
    sprite = visible_sprite
    @seen_frames = sprite ? @seen_frames + 1 : 0
    return false if @seen_frames < SETTLE_FRAMES
    other = remote_entries.values.first.character.outfit.to_a
    report("OK   #{Multiplayer::LocalPlayer.name} sees the other player at #{sprite.x},#{sprite.y} wearing #{other} (#{diagnosis})")
    Graphics.snap_to_bitmap.to_file(SCREENSHOT)
    true
  end

  def self.check_team
    size = [Multiplayer::DuelParty.available_count, Multiplayer::InteractionMenu::MAX_PARTY_SIZE].min
    rules = Multiplayer::Duel::Rules.new(size, 0, true, 60)
    party = Multiplayer::DuelParty.for_rules(rules)
    raise "the team cannot be encoded for a duel" unless party
    report("OK   team of #{party.size} encodes for a duel: #{party.map { |pokemon| pokemon["species"] }.join(" ")}")
  end

  def self.update
    @frame += 1
    if @passed_at
      finish("PASS") if @frame - @passed_at > LINGER_FRAMES
      return
    end
    finish("FAIL timeout: #{diagnosis}") if @frame > TIMEOUT_FRAMES
    return unless check_sight
    check_team
    @passed_at = @frame
  rescue SystemExit
    raise
  rescue Exception => e
    finish("FAIL #{e.class}: #{e.message}\n#{(e.backtrace || []).first(8).join("\n")}")
  end
end

class Scene_Intro
  def main
    if File.exist?(PresenceTest::SAVE_FILE)
      Game.load(SaveData.read_from_file(PresenceTest::SAVE_FILE))
      PresenceTest.report("OK   loaded #{PresenceTest::SAVE_FILE} as #{$Trainer.name}")
    else
      Game.start_new
      pbChangePlayer(0)
    end
    x, y, direction = PresenceTest::SPOTS.fetch(PresenceTest::ROLE)
    $MapFactory.setup(PresenceTest::MEETING_MAP)
    $game_player.moveto(x, y)
    $game_player.direction = direction
    $game_player.refresh
    $scene = Scene_Map.new
  end
end

File.delete(PresenceTest::RESULT_FILE) if File.exist?(PresenceTest::RESULT_FILE)
Events.onMapUpdate += proc { |_sender, _e| PresenceTest.update }
