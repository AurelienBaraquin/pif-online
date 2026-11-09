module Multiplayer
  # Knows who is visible and publishes the local player. Engine-independent:
  # game_hooks/presence turns this data into sprites.
  class Presence
    State = Struct.new(:map, :x, :y, :dir, :speed)
    RemotePlayer = Struct.new(:id, :name, :appearance, :state)

    FEATURE_NAME = :presence

    def initialize(client)
      @client = client
      @players = {}
      reset_published
      client.on_ready { reset_published }
      client.on_lost { @players = {} }
      client.on("player_joined") { |data| add_player(data) }
      client.on("player_moved") { |data| update_player(data["id"].to_i, state: parse_state(data["state"])) }
      client.on("player_appearance") { |data| update_player(data["id"].to_i, appearance: parse_appearance(data["appearance"])) }
      client.on("player_left") { |data| remove_player(data["id"].to_i) }
    end

    def players_on(map_id)
      @players.values.select { |player| player.state.map == map_id }
    end

    # Sends only what changed. Interest goes first so that the server can
    # answer with the players already present.
    def publish(state, appearance, interest)
      return unless @client.ready?
      publish_interest(interest)
      publish_appearance(appearance)
      publish_state(state)
    end

    private

    def reset_published
      @published_state = nil
      @published_appearance = nil
      @published_interest = nil
    end

    def publish_interest(interest)
      return if interest == @published_interest
      @published_interest = interest
      @client.deliver("interest", { "maps" => interest })
    end

    def publish_appearance(appearance)
      return if appearance == @published_appearance
      @published_appearance = appearance
      @client.deliver("appearance", appearance)
    end

    def publish_state(state)
      return if state == @published_state
      @published_state = state
      @client.deliver("move", {
        "map" => state.map, "x" => state.x, "y" => state.y, "dir" => state.dir, "speed" => state.speed
      })
    end

    def add_player(data)
      id = data["id"].to_i
      @players = @players.merge(
        id => RemotePlayer.new(id, data["name"], parse_appearance(data["appearance"]), parse_state(data["state"]))
      )
    end

    def update_player(id, state: nil, appearance: nil)
      player = @players[id]
      return unless player
      updated = RemotePlayer.new(id, player.name, appearance || player.appearance, state || player.state)
      @players = @players.merge(id => updated)
    end

    def remove_player(id)
      @players = @players.reject { |key, _player| key == id }
    end

    # The game's JSON parser returns every number as a Float.
    def parse_state(data)
      State.new(data["map"].to_i, data["x"].to_i, data["y"].to_i, data["dir"].to_i, data["speed"].to_i)
    end

    def parse_appearance(data)
      data.transform_values { |value| value.is_a?(Numeric) ? value.to_i : value }
    end
  end

  Runtime.register_feature(Presence::FEATURE_NAME) { |client| Presence.new(client) }
end
