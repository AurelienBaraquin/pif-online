require "socket"

module Multiplayer
  # Owns the TCP socket on a background thread and reconnects when it drops.
  # The game thread only exchanges lines with it through two queues.
  class Connection
    Event = Struct.new(:kind, :line)

    CONNECTED = :connected
    DISCONNECTED = :disconnected
    LINE = :line

    PING_LINE = "{\"t\":\"ping\"}"
    PING_INTERVAL = 5
    IDLE_TIMEOUT = 15
    CONNECT_TIMEOUT = 5
    MIN_RETRY_DELAY = 1
    MAX_RETRY_DELAY = 30
    STABLE_SESSION_SECONDS = 10
    POLL_INTERVAL = 0.02
    SLEEP_STEP = 0.1
    READ_SIZE = 4096
    MAX_LINE_BYTES = 16 * 1024
    MAX_QUEUE_SIZE = 2048

    def initialize(config)
      @config = config
      @inbound = Queue.new
      @outbound = Queue.new
      @running = false
      @connected = false
    end

    def start
      return if @running
      @running = true
      Thread.new { run }
    end

    # Returns at once: the thread notices the flag and finishes on its own, so
    # the game never waits for a pending connection attempt.
    def stop
      @running = false
    end

    # Lines sent while disconnected are dropped: the game state is republished
    # in full after each reconnection.
    def send_line(line)
      @outbound << line if @connected && @outbound.size < MAX_QUEUE_SIZE
    end

    def poll_event
      @inbound.empty? ? nil : @inbound.pop(true)
    end

    private

    def run
      delay = MIN_RETRY_DELAY
      while @running
        socket = open_socket
        delay = MIN_RETRY_DELAY if socket && timed_session(socket) >= STABLE_SESSION_SECONDS
        wait(delay)
        delay = [delay * 2, MAX_RETRY_DELAY].min
      end
    rescue StandardError => e
      Log.write("connection thread stopped: #{e.class}: #{e.message}")
    end

    # A server that accepts then refuses a client must not reset the backoff,
    # so only a session that lasted counts as a success.
    def timed_session(socket)
      started = now
      run_session(socket)
      now - started
    end

    def open_socket
      socket = TCPSocket.new(@config.host, @config.port, connect_timeout: CONNECT_TIMEOUT)
      socket.setsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY, 1)
      socket
    rescue SystemCallError, SocketError, IOError => e
      Log.write("cannot reach #{@config.host}:#{@config.port}: #{e.class}: #{e.message}")
      nil
    end

    def run_session(socket)
      @outbound.clear
      @connected = true
      @inbound << Event.new(CONNECTED, nil)
      pump(socket)
    rescue SystemCallError, IOError => e
      Log.write("connection lost: #{e.class}: #{e.message}")
    ensure
      @connected = false
      close_quietly(socket)
      @inbound << Event.new(DISCONNECTED, nil)
    end

    def pump(socket)
      buffer = String.new(encoding: Encoding::BINARY)
      last_received = last_ping = now
      while @running
        if read_available(socket, buffer)
          last_received = now
        end
        flush_outbound(socket)
        if now - last_ping >= PING_INTERVAL
          socket.write(PING_LINE, "\n")
          last_ping = now
        end
        return if now - last_received >= IDLE_TIMEOUT || @inbound.size >= MAX_QUEUE_SIZE
      end
    end

    def read_available(socket, buffer)
      return false unless IO.select([socket], nil, nil, POLL_INTERVAL)
      chunk = socket.read_nonblock(READ_SIZE, exception: false)
      return false if chunk == :wait_readable
      raise EOFError, "closed by server" if chunk.nil?
      buffer << chunk
      publish_lines(buffer)
      true
    end

    def publish_lines(buffer)
      while (index = buffer.index("\n"))
        line = buffer.slice!(0, index + 1).chomp
        @inbound << Event.new(LINE, line.force_encoding(Encoding::UTF_8))
      end
      raise IOError, "line too long" if buffer.bytesize > MAX_LINE_BYTES
    end

    def flush_outbound(socket)
      socket.write(@outbound.pop(true), "\n") until @outbound.empty?
    end

    def wait(seconds)
      deadline = now + seconds
      sleep(SLEEP_STEP) while @running && now < deadline
    end

    def close_quietly(socket)
      socket.close
    rescue SystemCallError, IOError
      nil
    end

    def now
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end
