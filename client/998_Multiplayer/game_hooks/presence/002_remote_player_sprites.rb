module Multiplayer
  class RemotePlayerSprite < Sprite_Character
    def initialize(viewport, character)
      super(viewport, character)
      make_shadow
    end

    def checkModifySpriteGraphics(_character); end

    def updateCharacterBitmap
      outfit = @character.outfit
      wrapper = AnimatedBitmap.new(getBaseOverworldSpriteFilename("walk", outfit.skin_tone))
      begin
        wrapper.bitmap = generateClothedBitmapStatic(outfit)
      rescue *Guard::RECOVERABLE => e
        Log.write("outfit fallback for #{outfit.to_a.inspect}: #{e.class}: #{e.message}")
      end
      wrapper
    end
  end

  # Displays the remote players of one map, in that map's spriteset. Spritesets
  # already follow connected maps and are rebuilt on every map transfer.
  class RemotePlayerSprites
    GUARD_SITE = "presence.sprites"

    def initialize(viewport, map)
      @viewport = viewport
      @map = map
      @entries = {}
      @disposed = false
    end

    def update
      return if @disposed
      Guard.run(GUARD_SITE) { refresh }
      clear if Guard.tripped?(GUARD_SITE)
    end

    def dispose
      return if @disposed
      clear
      @disposed = true
    end

    def disposed?
      @disposed
    end

    private

    Entry = Struct.new(:character, :sprite)

    def refresh
      presence = Runtime.feature(Presence::FEATURE_NAME)
      players = presence ? presence.players_on(@map.map_id) : []
      visible_ids = players.map(&:id)
      remove_absent(visible_ids)
      players.each { |player| refresh_player(player) }
    end

    def remove_absent(visible_ids)
      @entries.keys.reject { |id| visible_ids.include?(id) }.each do |id|
        @entries.delete(id).sprite.dispose
      end
    end

    def refresh_player(player)
      entry = @entries[player.id] ||= create_entry(player)
      entry.character.sync(player)
      entry.character.update
      entry.sprite.update
    end

    def create_entry(player)
      character = RemoteCharacter.new(@map, player)
      Entry.new(character, RemotePlayerSprite.new(@viewport, character))
    end

    def clear
      @entries.each_value { |entry| entry.sprite.dispose }
      @entries.clear
    end
  end
end
