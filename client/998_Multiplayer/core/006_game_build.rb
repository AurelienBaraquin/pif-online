require "zlib"

module Multiplayer
  # Identifies what a battle's outcome depends on. Duels simulate the same battle
  # on both clients, so two different builds would drift apart.
  module GameBuild
    DATA_FILES = %w[abilities items moves species types].map { |name| "Data/#{name}.dat" }.freeze
    SCRIPT_FILES = "Data/Scripts/**/*.rb"
    UNKNOWN = "0"

    # An unreadable file (locked by an antivirus, say) only costs duels: the
    # value matches no real build, while the shared world keeps working.
    def self.fingerprint
      @fingerprint ||= format("%08x", Zlib.crc32(sources.join))
    rescue SystemCallError, IOError => e
      Log.write("cannot fingerprint the game: #{e.class}: #{e.message}")
      UNKNOWN
    end

    # Copies of a game can differ by line endings alone.
    def self.sources
      data = DATA_FILES.select { |path| File.file?(path) }.map { |path| File.binread(path) }
      data + Dir.glob(SCRIPT_FILES).sort.map { |path| File.binread(path).gsub("\r\n", "\n") }
    end
    private_class_method :sources
  end
end
