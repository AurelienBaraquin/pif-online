module Multiplayer
  # Reads the local player from the game and clamps every value to what the
  # protocol accepts, because the server disconnects on invalid content.
  module LocalPlayer
    ASSET_NAME = /\A[A-Za-z0-9_ .-]{1,64}\z/.freeze
    VALID_DIRECTIONS = [2, 4, 6, 8].freeze
    MAX_INTEREST = 16
    MAX_NAME_LENGTH = 32
    MAX_COORDINATE = 9999
    MAX_SKIN = 99
    MAX_COLOR = 1_000_000
    DEFAULT_NAME = "Trainer"

    def self.name
      cleaned = $Trainer.name.to_s.scrub("").gsub(/[[:cntrl:]]/, "")[0, MAX_NAME_LENGTH]
      cleaned.empty? ? DEFAULT_NAME : cleaned
    end

    def self.state
      Presence::State.new(
        $game_map.map_id,
        $game_player.x.clamp(0, MAX_COORDINATE),
        $game_player.y.clamp(0, MAX_COORDINATE),
        VALID_DIRECTIONS.include?($game_player.direction) ? $game_player.direction : 2,
        $game_player.move_speed.round.clamp(1, 6)
      )
    end

    def self.appearance
      {
        "skin" => integer($Trainer.skin_tone, MAX_SKIN, 0),
        "clothes" => asset($Trainer.clothes),
        "hair" => asset($Trainer.hair),
        "hat" => asset($Trainer.hat),
        "hat2" => asset($Trainer.hat2),
        "clothes_color" => integer($Trainer.clothes_color, MAX_COLOR, -MAX_COLOR),
        "hair_color" => integer($Trainer.hair_color, MAX_COLOR, -MAX_COLOR),
        "hat_color" => integer($Trainer.hat_color, MAX_COLOR, -MAX_COLOR),
        "hat2_color" => integer($Trainer.hat2_color, MAX_COLOR, -MAX_COLOR)
      }
    end

    def self.interest
      $MapFactory.maps.map(&:map_id).uniq.sort.first(MAX_INTEREST)
    end

    def self.asset(value)
      return nil if value.nil?
      text = value.to_s
      text.match?(ASSET_NAME) && !text.include?("..") ? text : nil
    end

    def self.integer(value, max, min)
      value.is_a?(Numeric) ? value.to_i.clamp(min, max) : 0
    end
  end
end
