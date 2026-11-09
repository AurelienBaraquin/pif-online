# Saved servers. The overlay stays offline until the player joins a server from
# the in-game menu, so installing it never changes the single-player game.

# F12 re-evaluates every script in the same process: end the previous session.
Multiplayer::Runtime.stop if defined?(Multiplayer::Runtime)

module Multiplayer
  # Must match Version in server/internal/protocol/protocol.go.
  PROTOCOL_VERSION = 6
  CONFIG_FILE = "multiplayer.json"
  LOG_FILE = "multiplayer.log"
  DEFAULT_PORT = 7777

  Config = Struct.new(:host, :port) do
    def to_s
      port == DEFAULT_PORT ? host : "#{host}:#{port}"
    end

    def to_wire
      { "host" => host, "port" => port }
    end
  end

  # The player's saved servers and the one to connect to when a game is loaded,
  # if any. Every change returns a new book.
  ServerBook = Struct.new(:servers, :active) do
    def add(server)
      servers.include?(server) ? self : ServerBook.new(servers + [server], active)
    end

    def remove(server)
      ServerBook.new(servers - [server], active == server ? nil : active)
    end

    def with_active(server)
      ServerBook.new(servers, server)
    end
  end

  module Settings
    HOST_PATTERN = /\A[A-Za-z0-9](?:[A-Za-z0-9.-]{0,251}[A-Za-z0-9])?\z/.freeze
    ADDRESS_PATTERN = /\A([^:\s]+)(?::(\d{1,5}))?\z/.freeze
    PORTS = (1..65_535).freeze
    EMPTY_BOOK = ServerBook.new([], nil).freeze

    # Returns a Config for text such as "play.example.org" or "10.0.0.2:7777",
    # or nil when it is not a valid address.
    def self.parse_address(text)
      match = ADDRESS_PATTERN.match(text.to_s.strip)
      return nil unless match && match[1].match?(HOST_PATTERN)
      port = match[2] ? match[2].to_i : DEFAULT_PORT
      PORTS.cover?(port) ? Config.new(match[1], port) : nil
    end

    # The book in use, read from disk the first time.
    def self.book
      @book ||= load
    end

    # Replaces the book in use and saves it. Returns whether the save succeeded.
    def self.update(book)
      @book = book
      save(book)
    end

    # A missing or broken file reads as an empty book.
    def self.load(path = CONFIG_FILE)
      return EMPTY_BOOK unless File.exist?(path)
      data = HTTPLite::JSON.parse(File.read(path))
      servers = data.fetch("servers").map { |entry| server_from(entry) }
      ServerBook.new(servers, data["active"] && server_from(data["active"]))
    rescue *Guard::RECOVERABLE, KeyError => e
      Log.write("#{path}: #{e.class}: #{e.message}")
      EMPTY_BOOK
    end

    def self.save(book, path = CONFIG_FILE)
      temporary = "#{path}.tmp"
      data = { "servers" => book.servers.map(&:to_wire), "active" => book.active&.to_wire }
      File.write(temporary, HTTPLite::JSON.stringify(data))
      File.rename(temporary, path)
      true
    rescue SystemCallError, IOError => e
      Log.write("#{path}: #{e.class}: #{e.message}")
      false
    end

    def self.server_from(entry)
      port = entry["port"]
      valid = entry["host"].to_s.match?(HOST_PATTERN) && port.is_a?(Numeric) && PORTS.cover?(port.to_i)
      raise ArgumentError, "invalid server entry" unless valid
      Config.new(entry["host"], port.to_i)
    end
    private_class_method :server_from
  end
end
