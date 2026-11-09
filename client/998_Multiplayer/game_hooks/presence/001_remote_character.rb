module Multiplayer
  # A remote player on one map. It replays the positions received from the
  # server and bypasses the event system, so that it can never trigger gameplay
  # (encounters, tile events, step counters) on the local game.
  class RemoteCharacter < Game_Character
    Outfit = Struct.new(:skin_tone, :clothes, :hair, :hat, :hat2,
                        :clothes_color, :hair_color, :hat_color, :hat2_color)

    # The game's shadow system reads @event.pages on every non-player character.
    # An event without pages makes it skip this character instead of raising.
    EVENT_WITHOUT_PAGES = Struct.new(:pages).new([].freeze).freeze

    SNAP_DISTANCE = 4
    CATCH_UP_FACTOR = 2

    attr_reader :outfit

    def initialize(map, player)
      super(map)
      @event = EVENT_WITHOUT_PAGES
      @through = true
      @revision = 0
      @state = nil
      sync(player)
    end

    def name
      "remote_player"
    end

    def active?
      true
    end

    def triggerLeaveTile; end

    def sync(player)
      apply_appearance(player.appearance)
      apply_state(player.state)
    end

    def update
      @moved_last_frame = @moved_this_frame
      @moved_this_frame = moving?
      advance if @moved_this_frame
      update_pattern
    end

    private

    def apply_appearance(appearance)
      return if appearance == @appearance
      @appearance = appearance
      @outfit = build_outfit(appearance)
      @revision += 1
      @character_name = "multiplayer_#{@revision}"
    end

    def build_outfit(data)
      Outfit.new(data["skin"], data["clothes"], data["hair"], data["hat"], data["hat2"],
                 data["clothes_color"], data["hair_color"], data["hat_color"], data["hat2_color"])
    end

    def apply_state(state)
      return if state == @state
      first_placement = @state.nil?
      @state = state
      self.move_speed = state.speed
      @direction = state.dir
      if first_placement || tiles_behind(state) > SNAP_DISTANCE
        moveto(state.x, state.y)
      else
        @x = state.x
        @y = state.y
      end
      calculate_bush_depth
    end

    def tiles_behind(state)
      [(state.x - @real_x / Game_Map::REAL_RES_X).abs, (state.y - @real_y / Game_Map::REAL_RES_Y).abs].max
    end

    def advance
      distance = move_speed_real * (tiles_behind(@state) > 1 ? CATCH_UP_FACTOR : 1)
      @real_x = step_towards(@real_x, @x * Game_Map::REAL_RES_X, distance)
      @real_y = step_towards(@real_y, @y * Game_Map::REAL_RES_Y, distance)
      @anime_count += 1
    end

    def step_towards(current, target, distance)
      return [current + distance, target].min if current < target
      [current - distance, target].max
    end
  end
end
