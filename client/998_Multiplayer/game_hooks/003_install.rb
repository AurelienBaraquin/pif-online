# Connects the overlay to the game. This file and the classes in this folder are
# the only code that depends on the game's internals.
module Multiplayer
  module Install
    TICK_SITE = "runtime.tick"
    PUBLISH_SITE = "presence.publish"
    @config_loaded = false
    @config = nil

    def self.tick
      Guard.run(TICK_SITE) do
        Runtime.stop if Runtime.running? && $scene.is_a?(Scene_Intro)
        Runtime.tick
      end
    end

    def self.on_map_update
      Guard.run(PUBLISH_SITE) do
        ensure_started
        presence = Runtime.feature(Presence::FEATURE_NAME)
        presence&.publish(LocalPlayer.state, LocalPlayer.appearance, LocalPlayer.interest)
      end
    end

    def self.ensure_started
      return if Runtime.running?
      unless @config_loaded
        @config = Settings.load
        @config_loaded = true
      end
      Runtime.start(@config, LocalPlayer.name) if @config && $Trainer
    end

    # Graphics outlives an F12 reload, unlike the script classes: aliasing it
    # twice would make update call itself.
    def self.hook_graphics_update
      return if Graphics.respond_to?(:multiplayer_original_update)
      class << Graphics
        alias_method :multiplayer_original_update, :update

        def update
          multiplayer_original_update
          Multiplayer::Install.tick
        end
      end
    end

    def self.apply
      violations = EngineContract.violations
      unless violations.empty?
        Log.write("incompatible game version, overlay disabled: #{violations.join(", ")}")
        return
      end
      hook_graphics_update
      Events.onMapUpdate += proc { |_sender, _e| on_map_update }
      Events.onSpritesetCreate += proc do |_sender, e|
        spriteset, viewport = e
        spriteset.addUserSprite(RemotePlayerSprites.new(viewport, spriteset.map))
      end
    end
  end
end

Multiplayer::Install.apply
