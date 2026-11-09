module Multiplayer
  # Lifecycle of the active multiplayer session. A feature registers a factory
  # here at load time and receives the client when a session starts.
  module Runtime
    @factories = {}
    @features = {}
    @client = nil

    def self.register_feature(name, &factory)
      raise ArgumentError, "duplicate feature #{name}" if @factories.key?(name)
      @factories[name] = factory
    end

    def self.running?
      !@client.nil?
    end

    def self.start(config, player_name)
      return if running?
      @client = Client.new(config, player_name)
      @features = @factories.map { |name, factory| [name, factory.call(@client)] }.to_h
      @client.start
    end

    def self.stop
      return unless running?
      @client.stop
      @client = nil
      @features = {}
    end

    def self.tick
      @client&.tick
    end

    def self.feature(name)
      @features[name]
    end
  end
end
