# Runs inside the game's mkxp-z runtime and reports which networking
# primitives work there. Results go to probe_result.txt next to the executable.

PROBE_RESULT_FILE = "probe_result.txt"
PROBE_ROUND_TRIPS = 1000
PROBE_MAX_FRAMES = 600

def probe_log(line)
  File.open(PROBE_RESULT_FILE, "a") { |file| file.puts(line) }
end

def probe_step(name)
  value = yield
  probe_log("OK   #{name}: #{value}")
  true
rescue Exception => e
  probe_log("FAIL #{name}: #{e.class}: #{e.message}")
  false
end

def probe_echo_server(server)
  client = server.accept
  while (line = client.gets)
    client.write(line)
  end
ensure
  client&.close
end

def probe_round_trips(port)
  socket = TCPSocket.new("127.0.0.1", port)
  socket.setsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY, 1)
  PROBE_ROUND_TRIPS.times do |index|
    socket.write("#{index}\n")
    raise "bad echo at #{index}" unless socket.gets.to_i == index
  end
  socket
end

def probe_threaded_echo
  server = TCPServer.new("127.0.0.1", 0)
  port = server.addr[1]
  Thread.new { probe_echo_server(server) }
  started = Time.now
  worker = Thread.new { probe_round_trips(port) }
  frames = 0
  while worker.alive? && frames < PROBE_MAX_FRAMES
    Graphics.update
    frames += 1
  end
  raise "round trips did not finish in #{frames} frames" if worker.alive?
  socket = worker.value
  elapsed_ms = ((Time.now - started) * 1000).round
  probe_nonblocking_read(socket)
  "#{PROBE_ROUND_TRIPS} round trips in #{elapsed_ms}ms over #{frames} rendered frames"
end

def probe_nonblocking_read(socket)
  result = socket.read_nonblock(16, exception: false)
  raise "expected :wait_readable, got #{result.inspect}" unless result == :wait_readable
end

begin
  File.delete(PROBE_RESULT_FILE) if File.exist?(PROBE_RESULT_FILE)
  probe_log("RUBY #{RUBY_VERSION} #{RUBY_PLATFORM}")
  socket_loaded = probe_step("require socket") { require "socket" }
  if socket_loaded
    probe_step("threaded echo with non-blocking read") { probe_threaded_echo }
  end
  probe_step("require fiddle") { require "fiddle" }
  probe_step("require json") { require "json" }
  probe_log("DONE")
rescue Exception => e
  probe_log("FATAL #{e.class}: #{e.message}")
end
exit
