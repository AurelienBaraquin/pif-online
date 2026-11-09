module Multiplayer
  # Closes the party and summary screens still open when a duel is aborted:
  # their own loops never reach their cleanup.
  module DuelOverlays
    @open = []

    class << self
      attr_reader :open
    end

    def self.track(scene)
      @open = @open + [scene]
    end

    def self.untrack(scene)
      @open = @open.reject { |entry| entry.equal?(scene) }
    end

    def self.open?
      !@open.empty?
    end

    def self.close_all
      @open.reverse_each do |scene|
        begin
          scene.pbEndScene
        rescue *Guard::RECOVERABLE => e
          Log.write("duel overlay cleanup: #{e.class}: #{e.message}")
        end
      end
      @open = []
    end

    # Prepended to the party and summary scenes.
    module Tracked
      def pbStartScene(*args, &block)
        DuelOverlays.track(self) if DuelRunner.running
        super
      end

      def pbEndScene(*args, &block)
        DuelOverlays.untrack(self)
        super
      end
    end
  end

  # The countdown shown while the player chooses. Display only: the server owns
  # the timer and ends the duel when it runs out.
  class DuelTurnTimer
    WIDTH = 72
    HEIGHT = 30
    MARGIN = 8
    Z = 100_000
    URGENT_SECONDS = 10
    BACKGROUND = Color.new(0, 0, 0, 160)
    NORMAL_COLOR = Color.new(248, 248, 248)
    URGENT_COLOR = Color.new(248, 96, 96)

    def initialize(link)
      @link = link
      @viewport = Viewport.new(Graphics.width - WIDTH - MARGIN, MARGIN, WIDTH, HEIGHT)
      @viewport.z = Z
      @sprite = Sprite.new(@viewport)
      @sprite.bitmap = Bitmap.new(WIDTH, HEIGHT)
      pbSetSystemFont(@sprite.bitmap)
      update
    end

    def update
      seconds = @link.seconds_left
      return if seconds == @shown
      @shown = seconds
      bitmap = @sprite.bitmap
      bitmap.fill_rect(0, 0, WIDTH, HEIGHT, BACKGROUND)
      bitmap.font.color = seconds <= URGENT_SECONDS ? URGENT_COLOR : NORMAL_COLOR
      bitmap.draw_text(0, 0, WIDTH, HEIGHT, seconds.to_s, 1)
    end

    def dispose
      @sprite.bitmap.dispose
      @sprite.dispose
      @viewport.dispose
    end
  end
end
