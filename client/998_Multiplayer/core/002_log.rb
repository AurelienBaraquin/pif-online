module Multiplayer
  module Log
    def self.write(message)
      File.open(LOG_FILE, "a") { |file| file.puts("[#{Time.now}] #{message}") }
    rescue SystemCallError
      nil
    end
  end

  # Shields the game from overlay failures. A site that raises is logged once
  # and then disabled, so a bug costs a feature and never the player's session.
  module Guard
    # MKXPError, raised by the engine's native code, is not a StandardError.
    RECOVERABLE = [StandardError, (MKXPError if defined?(MKXPError))].compact.freeze

    @tripped = {}

    def self.run(site)
      return nil if @tripped[site]
      yield
    rescue *RECOVERABLE => e
      @tripped[site] = true
      Log.write("#{site} disabled: #{e.class}: #{e.message}\n#{(e.backtrace || []).first(8).join("\n")}")
      nil
    end

    def self.tripped?(site)
      @tripped.key?(site)
    end
  end
end
