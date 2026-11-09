module Multiplayer
  # Protocol session, driven from the game thread. Features subscribe to message
  # types and to the ready/lost lifecycle.
  class Client
    MAX_EVENTS_PER_TICK = 128
    FATAL_ERROR_CODES = %w[version_mismatch bad_message].freeze

    attr_reader :player_id

    def initialize(config, player_name)
      @player_name = player_name
      @connection = Connection.new(config)
      @handlers = {}
      @ready_callbacks = []
      @lost_callbacks = []
      @ready = false
      @player_id = nil
    end

    def ready?
      @ready
    end

    def on(type, &handler)
      raise ArgumentError, "duplicate handler for #{type}" if @handlers.key?(type)
      @handlers[type] = handler
    end

    def on_ready(&callback)
      @ready_callbacks << callback
    end

    def on_lost(&callback)
      @lost_callbacks << callback
    end

    def start
      @connection.start
    end

    def stop
      @connection.stop
      mark_lost
    end

    def tick
      MAX_EVENTS_PER_TICK.times do
        event = @connection.poll_event
        return unless event
        process(event)
      end
    end

    def deliver(type, data)
      transmit(type, data) if @ready
    end

    private

    def transmit(type, data)
      # The game's encoder pretty-prints; a real newline never occurs inside a
      # JSON string, so removing them all yields one protocol line.
      @connection.send_line(HTTPLite::JSON.stringify({ "t" => type, "d" => data }).delete("\n"))
    end

    def process(event)
      case event.kind
      when Connection::CONNECTED
        transmit("hello", { "v" => PROTOCOL_VERSION, "name" => @player_name })
      when Connection::DISCONNECTED
        mark_lost
      when Connection::LINE
        receive(event.line)
      end
    end

    def mark_lost
      return unless @ready
      @ready = false
      @player_id = nil
      @lost_callbacks.each(&:call)
    end

    def receive(line)
      message = HTTPLite::JSON.parse(line)
      type = message["t"]
      data = message["d"]
      case type
      when "welcome" then mark_ready(data)
      when "error" then handle_error(data)
      when "pong" then nil
      else @handlers[type]&.call(data)
      end
    rescue *Guard::RECOVERABLE => e
      Log.write("ignored message #{line[0, 200]}: #{e.class}: #{e.message}")
    end

    def mark_ready(data)
      @player_id = data["id"].to_i
      @ready = true
      @ready_callbacks.each(&:call)
    end

    def handle_error(data)
      Log.write("server error #{data["code"]}: #{data["message"]}")
      @connection.stop if FATAL_ERROR_CODES.include?(data["code"])
    end
  end
end
