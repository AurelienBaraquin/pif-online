module Multiplayer
  # Lists what the overlay needs from the game. A game update that removes one
  # of these disables the overlay at startup instead of crashing later.
  module EngineContract
    REQUIRED_INSTANCE_METHODS = {
      "Game_Character" => %i[moveto update_pattern calculate_bush_depth screen_x screen_y screen_z],
      "Sprite_Character" => %i[update dispose updateCharacterBitmap checkModifySpriteGraphics make_shadow],
      "Spriteset_Map" => %i[addUserSprite map],
      "AnimatedBitmap" => %i[bitmap bitmap=],
      "Scene_Map" => %i[update],
      "Trainer" => %i[able_party]
    }.freeze
    REQUIRED_GLOBAL_METHODS = %i[getBaseOverworldSpriteFilename generateClothedBitmapStatic pbFacingTile pbMessage pbConfirmMessage pbMapInterpreterRunning?].freeze

    def self.violations
      missing = REQUIRED_INSTANCE_METHODS.flat_map do |class_name, methods|
        next ["class #{class_name}"] unless Object.const_defined?(class_name)
        klass = Object.const_get(class_name)
        methods.reject { |name| klass.method_defined?(name) }.map { |name| "#{class_name}##{name}" }
      end
      missing + REQUIRED_GLOBAL_METHODS.reject { |name| Object.private_method_defined?(name) || Object.method_defined?(name) }
    end
  end
end
