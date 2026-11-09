# Connection settings. The overlay stays inactive without a configuration file,
# so installing it never changes the single-player game on its own.

# F12 re-evaluates every script in the same process: end the previous session.
Multiplayer::Runtime.stop if defined?(Multiplayer::Runtime)

module Multiplayer
  # Must match Version in server/internal/protocol/protocol.go.
  PROTOCOL_VERSION = 5
  CONFIG_FILE = "multiplayer.json"
  LOG_FILE = "multiplayer.log"
  DEFAULT_PORT = 7777

  Config = Struct.new(:host, :port)

  module Settings
    # Returns a Config, or nil when multiplayer is not configured or disabled.
    def self.load(path = CONFIG_FILE)
      return nil unless File.exist?(path)
      data = HTTPLite::JSON.parse(File.read(path))
      return nil if data["enabled"] == false
      host = data["host"]
      unless host.is_a?(String) && !host.empty?
        Log.write("#{path}: \"host\" is required")
        return nil
      end
      port = data.fetch("port", DEFAULT_PORT)
      unless port.is_a?(Numeric) && port.to_i.between?(1, 65_535)
        Log.write("#{path}: \"port\" must be between 1 and 65535")
        return nil
      end
      Config.new(host, port.to_i)
    rescue *Guard::RECOVERABLE => e
      Log.write("#{path}: #{e.class}: #{e.message}")
      nil
    end
  end
end
