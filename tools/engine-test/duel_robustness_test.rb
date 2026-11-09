# Plays real duels in the real game against an in-process bot and checks that
# every way a duel can end closes the battle at once, with the right wording for
# both players, and that the next duel works. Loaded after
# battle_determinism_test.rb. Writes test_result.txt and screenshots.

module DuelRobustnessTest
  RESULT_FILE = "test_result.txt"
  RESTART_FLAG = "restart_server"
  MAX_FRAMES_PER_SCENARIO = 3600
  MAX_ABORT_FRAMES = 240
  MESSAGE_PRESS_INTERVAL = 30
  PARTY_SIZE = 2
  ADDRESS = Multiplayer::Config.new("127.0.0.1", 7777)
  Choice = Multiplayer::DuelLink::Choice
  LOCAL_FORFEITED = "You forfeited the duel."
  BOT_NAME = "Bot"

  Scenario = Struct.new(:name, :turn_seconds, :move, :local_text, :bot_text, :steps, :format)

  # Builds the bot's party: its move decides whether the local player faints.
  def self.bot_party(move)
    pokemon = {
      "species" => "BULBASAUR", "level" => 100, "form" => 0, "personal_id" => 1, "gender" => 0, "nature" => "HARDY",
      "ability" => "OVERGROW", "ability_index" => 0, "item" => nil, "happiness" => 70, "iv" => [31] * 6,
      "iv_maxed" => [false] * 6, "ev" => [0] * 6, "moves" => [{ "id" => move, "pp" => 20, "ppup" => 0 }],
      "name" => "Bulby", "shiny" => false, "head_shiny" => false, "body_shiny" => false,
      "hidden_power_type" => nil, "size_category" => nil, "pif_sprite" => nil
    }
    Array.new(PARTY_SIZE) { pokemon }
  end

  class BotParty
    attr_accessor :move

    def for_rules(_rules)
      DuelRobustnessTest.bot_party(@move)
    end

    def appearance
      {}
    end
  end

  class << self
    attr_reader :tap_button, :bot_link
  end

  # --- steps: each returns true when finished -------------------------------

  def self.after(frames)
    left = frames
    -> { (left -= 1) <= 0 }
  end

  def self.press(button)
    lambda do
      @tap_button = button
      true
    end
  end

  def self.action(&block)
    lambda do
      block.call
      @last_action_frame = @frame
      true
    end
  end

  def self.turn_timer
    Multiplayer::DuelRunner.scene&.instance_variable_get(:@turn_timer)
  end

  def self.timer_open
    -> { !turn_timer.nil? }
  end

  def self.overlay_open
    -> { Multiplayer::DuelOverlays.open? }
  end

  def self.snapshot(name)
    lambda do
      Graphics.snap_to_bitmap.to_file(name)
      true
    end
  end

  def self.bot_turn_received
    -> { !@bot_link.turn(1).nil? }
  end

  def self.bot_forfeit
    action do
      @must_close_promptly = true
      @bot_link.forfeit
    end
  end

  def self.bot_chooses
    action { @bot_link.send_choice(1, Array.new(@bot_link.format.side_size) { Choice.new("move", 0) }) }
  end

  def self.bot_disconnects
    action do
      @must_close_promptly = true
      @bot_gone = true
      @bot_client.stop
    end
  end

  def self.choose_first_move
    [timer_open, after(20), press(Input::USE), after(20), press(Input::USE)]
  end

  def self.open_party
    [timer_open, after(20), press(Input::DOWN), after(10), press(Input::USE), overlay_open, after(20)]
  end

  def self.local_battle
    Multiplayer::DuelRunner.scene.instance_variable_get(:@battle)
  end

  # The local player is on side 1: its first battler is 1 and its second is 3.
  def self.first_battler_chose_a_target
    action { raise "first battler's target lost: #{local_battle.choices[1]}" unless local_battle.choices[1][3] >= 0 }
  end

  def self.first_battler_cleared
    action { raise "first battler still chosen: #{local_battle.choices[1]}" unless local_battle.choices[1][0] == :None }
  end

  def self.choose_first_battler
    [timer_open, after(20), press(Input::USE), after(20), press(Input::USE), after(20), press(Input::USE), after(30)]
  end

  def self.scenarios
    [
      Scenario.new("doubles: opponent forfeits during the second battler's menu", 60, "GROWL", "Bot forfeited. You won the duel!", LOCAL_FORFEITED,
                   choose_first_battler + [first_battler_chose_a_target, bot_forfeit], "doubles"),
      Scenario.new("doubles: going back clears the first battler's choice", 60, "GROWL", "Bot forfeited. You won the duel!", LOCAL_FORFEITED,
                   choose_first_battler + [press(Input::BACK), after(30), first_battler_cleared, bot_forfeit], "doubles"),
      Scenario.new("doubles: the turn resolves with both local actions", 60, "GROWL", "Bot forfeited. You won the duel!", LOCAL_FORFEITED,
                   choose_first_battler + [press(Input::USE), after(20), press(Input::USE), after(20), press(Input::USE), after(20),
                                           bot_chooses, bot_turn_received, after(40), bot_forfeit], "doubles"),
      Scenario.new("forfeit while the fight menu is open", 60, "GROWL", "Bot forfeited. You won the duel!", LOCAL_FORFEITED,
                   [timer_open, after(20), snapshot("test_timer.png"), press(Input::USE), after(20), bot_forfeit]),
      Scenario.new("forfeit while the party screen is open", 60, "GROWL", "Bot forfeited. You won the duel!", LOCAL_FORFEITED,
                   open_party + [snapshot("test_party.png"), bot_forfeit]),
      Scenario.new("forfeit while messages play", 60, "GROWL", "Bot forfeited. You won the duel!", LOCAL_FORFEITED,
                   choose_first_move + [bot_chooses, bot_turn_received, after(40), bot_forfeit]),
      Scenario.new("local forfeit", 60, "GROWL", LOCAL_FORFEITED, "{local} forfeited. You won the duel!",
                   [timer_open, after(20), press(Input::DOWN), after(10), press(Input::RIGHT), after(10), press(Input::USE),
                    after(40), press(Input::USE)]),
      Scenario.new("opponent disconnects during the party screen", 60, "GROWL", "Bot disconnected. You won the duel!", nil,
                   open_party + [bot_disconnects]),
      Scenario.new("you ran out of time in the fight menu", 30, "GROWL", "You ran out of time. You lost the duel.",
                   "{local} ran out of time. You won the duel!",
                   [bot_chooses, timer_open, after(10), press(Input::USE)]),
      Scenario.new("both ran out of time", 30, "GROWL",
                   "Time ran out for both players. The duel ended without a winner.",
                   "Time ran out for both players. The duel ended without a winner.", []),
      Scenario.new("stalled replacement loses", 30, "SWIFT", "You ran out of time. You lost the duel.",
                   "{local} ran out of time. You won the duel!",
                   choose_first_move + [bot_chooses, overlay_open]),
      Scenario.new("forfeit during the replacement screen", 60, "SWIFT", "Bot forfeited. You won the duel!", LOCAL_FORFEITED,
                   choose_first_move + [bot_chooses, overlay_open, after(20), bot_forfeit]),
      Scenario.new("desync", 60, "GROWL", "The duel was cancelled because the two games disagreed.",
                   "The duel was cancelled because the two games disagreed.",
                   choose_first_move + [bot_chooses, bot_turn_received, action { @bot_link.send_hash(1, "x") }]),
      Scenario.new("server restart", 60, "GROWL", "The connection to the server was lost. The duel was cancelled.",
                   "The connection to the server was lost. The duel was cancelled.",
                   [timer_open, after(20), action { File.write(RESTART_FLAG, "") }])
    ]
  end

  # --- reporting and bookkeeping --------------------------------------------

  def self.report(line)
    File.open(RESULT_FILE, "a") { |file| file.puts(line) }
  end

  def self.finish(verdict)
    report(verdict)
    exit
  end

  def self.local_duel
    Multiplayer::Runtime.feature(Multiplayer::Duel::FEATURE_NAME)
  end

  def self.local_client
    Multiplayer::Runtime.instance_variable_get(:@client)
  end

  def self.local_name
    @bot_link.players[1 - @bot_link.side]["name"]
  end

  def self.around_message(message)
    @first_message_frame ||= @frame
    @messages << message
    @message_depth += 1
    @message_frame = 0
    yield
  ensure
    @message_depth -= 1
  end

  def self.press_for_message
    return if @message_depth.zero?
    @message_frame += 1
    @tap_button = Input::USE if (@message_frame % MESSAGE_PRESS_INTERVAL).zero?
  end

  # --- state machine, run after every frame ----------------------------------

  def self.start
    @frame = 0
    @scenario_start = 0
    @messages = []
    @message_depth = 0
    @message_frame = 0
    @scenarios = scenarios
    @party_source = BotParty.new
    connect_bot
    @state = :ready
  end

  def self.connect_bot
    @bot_client = Multiplayer::Client.new(ADDRESS, BOT_NAME)
    @bot_duel = Multiplayer::Duel.new(@bot_client, @party_source)
    @bot_client.start
  end

  def self.on_frame
    return unless @state
    @frame += 1
    @tap_button = nil
    @bot_client.tick
    press_for_message
    send("state_#{@state}")
    finish("FAIL #{current&.name} timed out in #{@state}") if current && @frame - @scenario_start > MAX_FRAMES_PER_SCENARIO
  rescue SystemExit
    raise
  rescue Exception => e
    finish("FAIL #{current&.name}: #{e.class}: #{e.message}\n#{(e.backtrace || []).first(8).join("\n")}")
  end

  def self.current
    @scenarios&.first
  end

  def self.state_ready
    if @bot_gone
      @bot_gone = false
      connect_bot
    end
    return unless $scene.is_a?(Scene_Map) && local_duel && local_client.ready? && local_duel.idle?
    return unless @bot_client.ready? && @bot_duel.idle? && @message_depth.zero? && !Multiplayer::DuelRunner.running
    @scenario_start = @frame
    @must_close_promptly = false
    @first_message_frame = nil
    @party_source.move = current.move
    @step_list = current.steps.dup
    rules = Multiplayer::Duel::Rules.new(PARTY_SIZE, 0, true, current.turn_seconds, [], current.format || "singles")
    @bot_duel.challenge(local_client.player_id, rules)
    @state = :starting
  end

  def self.state_starting
    invitation = local_duel.take_invitation
    local_duel.respond(invitation, true) if invitation
    link = @bot_duel.take_start
    return unless link
    @bot_link = link
    @last_action_frame = @frame
    @messages = []
    @first_message_frame = nil
    @state = :playing
  end

  def self.state_playing
    if (step = @step_list.first)
      @step_list.shift if step.call
    end
    verify_ending if ended?
  end

  def self.ended?
    !@messages.empty? && !Multiplayer::DuelRunner.running && @message_depth.zero? &&
      !@bot_link.ending.nil? && local_duel.idle?
  end

  def self.verify_ending
    name = current.name
    raise "local text #{@messages.inspect}" unless @messages == [current.local_text]
    verify_bot_text(name)
    raise "party or summary left open" if Multiplayer::DuelOverlays.open?
    raise "scene left active" unless Multiplayer::DuelRunner.scene.nil?
    raise "steps left: #{@step_list.size}" unless @step_list.empty?
    elapsed = @first_message_frame - @last_action_frame
    raise "slow abort: #{elapsed} frames" if @must_close_promptly && elapsed > MAX_ABORT_FRAMES
    report("OK   #{name} (ending shown #{elapsed} frames after last action)")
    @scenarios = @scenarios.drop(1)
    conclude if @scenarios.empty?
    @scenario_start = @frame
    @state = :ready
  end

  def self.verify_bot_text(name)
    return unless current.bot_text
    expected = current.bot_text.gsub("{local}", local_name)
    actual = Multiplayer::DuelRunner.outcome_text(@bot_link, @bot_link.ending)
    raise "#{name}: bot text #{actual.inspect}, want #{expected.inspect}" unless actual == expected
  end

  def self.conclude
    verify_reload_survival
    tripped = ["runtime.tick", "presence.publish", "interaction.menu", "duel.prompts", "duel.timer"].select { |site| Multiplayer::Guard.tripped?(site) }
    finish(tripped.empty? ? "PASS" : "FAIL guards tripped: #{tripped}")
  end

  # F12 redefines PBDebug.logonerr: the passthrough must survive that.
  def self.verify_reload_survival
    def PBDebug.logonerr
      yield
    rescue StandardError
      nil
    end
    Multiplayer::DuelRunner.instance_variable_set(:@running, true)
    begin
      PBDebug.logonerr { raise IOError, "probe" }
      raise "passthrough lost after reload"
    rescue IOError
      report("OK   error passthrough survives a script reload")
    ensure
      Multiplayer::DuelRunner.instance_variable_set(:@running, false)
    end
  end
end

alias duel_robustness_original_message pbMessage

def pbMessage(message, commands = nil, *args, &block)
  DuelRobustnessTest.around_message(message) do
    duel_robustness_original_message(message, commands, *args, &block)
  end
end

class << Graphics
  alias_method :duel_robustness_original_update, :update

  def update
    duel_robustness_original_update
    DuelRobustnessTest.on_frame
  end
end

class << Input
  alias_method :duel_robustness_original_trigger, :trigger?

  def trigger?(button)
    return true if DuelRobustnessTest.tap_button == button
    duel_robustness_original_trigger(button)
  end
end

class Scene_Intro
  OUTDOOR_MAP_NAME = /Littleroot|Oldale|Petalburg/i

  def main
    Game.start_new
    map_id, = load_data("Data/MapInfos.rxdata").find { |_id, info| info.name =~ OUTDOOR_MAP_NAME }
    $MapFactory.setup(map_id)
    pbChangePlayer(0)
    $game_player.refresh
    $Trainer.party = Array.new(DuelRobustnessTest::PARTY_SIZE) do
      pikachu = Pokemon.new(:PIKACHU, 5)
      pikachu.moves.clear
      pikachu.learn_move(:THUNDERSHOCK)
      pikachu
    end
    DuelRobustnessTest.start
  end
end

File.delete(DuelRobustnessTest::RESULT_FILE) if File.exist?(DuelRobustnessTest::RESULT_FILE)
