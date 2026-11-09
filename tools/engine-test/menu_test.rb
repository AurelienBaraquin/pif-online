# Drives the Multiplayer menu in the real game: real pause scene and address box,
# scripted choices for the message windows, a real server. Loaded after
# battle_determinism_test.rb. Writes test_result.txt and screenshots.

module MenuTest
  RESULT_FILE = "test_result.txt"
  PRESS_FRAME = 40
  LOCAL = "127.0.0.1"
  CLOSED = "127.0.0.1:7"

  @answers = []
  @messages = []
  @press_in = nil
  @typed = nil
  class << self
    attr_reader :messages
  end

  def self.report(line)
    File.open(RESULT_FILE, "a") { |file| file.puts(line) }
  end

  def self.script(*answers)
    @answers += answers
  end

  # Answers a command window with the first label matching the next answer.
  def self.answer(message, commands)
    @messages << message
    report("message: #{message} #{commands&.join(" | ")}")
    return 0 unless commands
    wanted = @answers.shift
    raise "no answer scripted for: #{message}" unless wanted
    return wanted.call if wanted.respond_to?(:call)
    commands.index { |label| label =~ wanted } || raise("no #{wanted} in #{commands}")
  end

  def self.check(description)
    raise "failed: #{description}" unless yield
    report("OK   #{description}")
  end

  def self.press_after(frames)
    @press_in = frames
  end

  # A press lasts one whole frame, like a real key: the scene may poll it after
  # other objects did.
  def self.on_frame
    @pressed = false
    return unless @press_in
    @press_in -= 1
    return unless @press_in <= 0
    @press_in = nil
    @pressed = true
    Graphics.snap_to_bitmap.to_file("test_menu_#{@messages.size}.png")
  end

  def self.press?
    @pressed
  end

  def self.typed_text
    text = @typed
    @typed = nil
    text
  end

  def self.type(text)
    @typed = text
    press_after(PRESS_FRAME)
  end

  def self.book
    Multiplayer::Settings.book
  end

  def self.status
    Multiplayer::Runtime.status
  end

  def self.pause_entry
    scene = PokemonPauseMenu_Scene.new
    scene.pbStartScene
    $PokemonTemp.menuLastChoice = 1
    script(lambda {
      $PokemonTemp.menuLastChoice = 2
      press_after(PRESS_FRAME)
      1
    })
    press_after(PRESS_FRAME)
    choice = scene.pbShowCommands(["First", "Last"])
    scene.pbEndScene
    check("the pause entry opens the menu and keeps the game's indices") { choice == 1 }
  end

  def self.address_box
    type("192.168.1.20")
    text = PIFMenuOriginal.free_text
    check("the address box reads the keyboard: #{text.inspect}") { text == "192.168.1.20" }
  end

  def self.invalid_address
    script(/Add a server/, /Back/)
    @free_text = "http://nope"
    Multiplayer::MultiplayerMenu.open
    check("an invalid address is refused") { @messages.include?("That address is not valid.") && book.servers.empty? }
  end

  attr_writer :free_text

  def self.free_text_answer
    @free_text
  end

  def self.join_and_leave
    @free_text = LOCAL
    script(/Add a server/, /Back/)
    Multiplayer::MultiplayerMenu.open
    check("adding a server joins it") { status == Multiplayer::Client::STATUS_READY }
    check("the active server is saved") { Multiplayer::Settings.load == book && book.active&.host == LOCAL }
    script(/Disconnect/, /Back/)
    Multiplayer::MultiplayerMenu.open
    check("disconnecting goes offline and stays offline") { status == :offline && book.active.nil? && book.servers.size == 1 }
  end

  def self.unreachable
    @free_text = CLOSED
    script(/Add a server/, /Back/)
    Multiplayer::MultiplayerMenu.open
    check("an unreachable server is explained") do
      status == :offline && book.active.nil? && @messages.any? { |text| text.start_with?("Cannot reach") }
    end
    script(/Remove a server/, ->{ 1 }, /Back/)
    Multiplayer::MultiplayerMenu.open
    check("a server can be removed") { book.servers.map(&:to_s) == [LOCAL] }
  end

  def self.with_protocol(version)
    original = Multiplayer::PROTOCOL_VERSION
    Multiplayer.send(:remove_const, :PROTOCOL_VERSION)
    Multiplayer.const_set(:PROTOCOL_VERSION, version)
    yield
  ensure
    Multiplayer.send(:remove_const, :PROTOCOL_VERSION)
    Multiplayer.const_set(:PROTOCOL_VERSION, original)
  end

  def self.version_mismatch
    with_protocol(999) do
      script(/Join/, /Back/)
      Multiplayer::MultiplayerMenu.open
    end
    check("a version mismatch is explained") do
      status == :offline && @messages.any? { |text| text.start_with?("This server runs another version") }
    end
  end

  def self.notices
    prompts = Multiplayer::ConnectionPrompts
    check("only meaningful status changes are announced") do
      prompts.text_for(:ready, :lost).start_with?("The connection") &&
        prompts.text_for(:lost, :ready).start_with?("Connection to the server restored") &&
        prompts.text_for(:connecting, :ready).nil? && prompts.text_for(:ready, :offline).nil?
    end
  end

  def self.run
    pause_entry
    address_box
    invalid_address
    join_and_leave
    unreachable
    version_mismatch
    notices
    tripped = Multiplayer::Guard.tripped?(Multiplayer::MultiplayerMenu::SITE)
    report(tripped ? "FAIL menu guard tripped" : "PASS")
  rescue SystemExit
    raise
  rescue Exception => e
    report("FAIL #{e.class}: #{e.message}\n#{(e.backtrace || []).first(8).join("\n")}")
  ensure
    exit
  end
end

module PIFMenuOriginal
  def self.free_text
    menu_test_original_free_text("Address:", "", false, 64, 320)
  end
end

alias menu_test_original_free_text pbMessageFreeText
alias menu_test_original_message pbMessage

def pbMessage(message, commands = nil, *_args)
  MenuTest.answer(message, commands)
end

def pbMessageFreeText(_message, _current, _password, _maxlength, _width = 240)
  MenuTest.free_text_answer
end

class << Graphics
  alias_method :menu_test_original_update, :update

  def update
    menu_test_original_update
    MenuTest.on_frame
  end
end

class << Input
  alias_method :menu_test_original_trigger, :trigger?
  alias_method :menu_test_original_triggerex, :triggerex?
  alias_method :menu_test_original_gets, :gets

  def trigger?(button)
    return true if button == Input::USE && MenuTest.press?
    menu_test_original_trigger(button)
  end

  def triggerex?(key)
    return true if key == :RETURN && MenuTest.press?
    menu_test_original_triggerex(key)
  end

  def gets
    MenuTest.typed_text || menu_test_original_gets
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
  end
end

class Scene_Map
  alias_method :menu_test_original_update, :update

  def update
    menu_test_original_update
    MenuTest.run
  end
end

File.delete(MenuTest::RESULT_FILE) if File.exist?(MenuTest::RESULT_FILE)
File.delete(Multiplayer::CONFIG_FILE) if File.exist?(Multiplayer::CONFIG_FILE)
