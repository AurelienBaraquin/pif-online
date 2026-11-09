# Exercises the client core and the presence feature against a real server,
# inside the game's Ruby runtime. Writes test_result.txt, ending with PASS or FAIL.

RESULT_FILE = "test_result.txt"
TEST_TIMEOUT = 8
ADDRESS = Multiplayer::Config.new("127.0.0.1", 7777)
APPEARANCE = {
  "skin" => 2, "clothes" => "red", "hair" => "1_painter", "hat" => nil, "hat2" => nil,
  "clothes_color" => 10, "hair_color" => 0, "hat_color" => 0, "hat2_color" => 0
}.freeze

def report(line)
  File.open(RESULT_FILE, "a") { |file| file.puts(line) }
end

class TestPeer
  attr_reader :client, :presence

  def initialize(name)
    @client = Multiplayer::Client.new(ADDRESS, name)
    @presence = Multiplayer::Presence.new(@client)
    @client.start
  end

  def state(x)
    Multiplayer::Presence::State.new(5, x, 3, 2, 3)
  end

  def publish(x)
    @presence.publish(state(x), APPEARANCE, [5])
  end
end

def wait_for(description, peers)
  deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + TEST_TIMEOUT
  until yield
    raise "timeout: #{description}" if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
    Graphics.update
    peers.each { |peer| peer.client.tick }
  end
  report("OK   #{description}")
end

def run_settings_checks
  File.write("t.json", '{"host":"example.org","port":1234}')
  config = Multiplayer::Settings.load("t.json")
  raise "config not parsed" unless config&.host == "example.org" && config.port == 1234
  File.write("t.json", '{"host":"example.org","enabled":false}')
  raise "disabled config loaded" if Multiplayer::Settings.load("t.json")
  File.write("t.json", "not json")
  raise "broken config loaded" if Multiplayer::Settings.load("t.json")
  raise "missing config loaded" if Multiplayer::Settings.load("absent.json")
  report("OK   settings accept valid files and reject others")
end

def run_guard_checks
  Multiplayer::Guard.run(:test) { raise ArgumentError, "expected" }
  raise "guard not tripped" unless Multiplayer::Guard.tripped?(:test)
  ran = false
  Multiplayer::Guard.run(:test) { ran = true }
  raise "tripped guard still runs" if ran
  report("OK   guard contains errors and disables the site")
end

def run_session_checks
  alice = TestPeer.new("Alice")
  bob = TestPeer.new("Bob é")
  peers = [alice, bob]
  wait_for("both clients receive welcome", peers) { alice.client.ready? && bob.client.ready? }

  alice.publish(4)
  bob.publish(8)
  wait_for("each client sees the other", peers) do
    alice.presence.players_on(5).size == 1 && bob.presence.players_on(5).size == 1
  end
  seen = bob.presence.players_on(5).first
  raise "wrong appearance: #{seen.appearance}" unless seen.appearance == APPEARANCE
  raise "wrong name: #{alice.presence.players_on(5).first.name}" unless alice.presence.players_on(5).first.name == "Bob é"

  alice.publish(5)
  wait_for("a move reaches the other client", peers) { bob.presence.players_on(5).first.state.x == 5 }

  alice.client.stop
  wait_for("a disconnection removes the player", [bob]) { bob.presence.players_on(5).empty? }
  bob.client.stop
end

begin
  File.delete(RESULT_FILE) if File.exist?(RESULT_FILE)
  report("MKXPError ancestors: #{defined?(MKXPError) ? MKXPError.ancestors.first(3) : "undefined"}")
  run_settings_checks
  run_guard_checks
  run_session_checks
  report("PASS")
rescue Exception => e
  report("FAIL #{e.class}: #{e.message}\n#{(e.backtrace || []).first(6).join("\n")}")
end
exit
