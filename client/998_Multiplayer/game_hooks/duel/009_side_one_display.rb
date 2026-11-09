module Multiplayer
  # Both clients simulate a duel with identical battler indices (index 0 is
  # side 0), and the simulation depends on it. The player on side 1 therefore
  # sees the same battle mirrored: only code that draws or words the battle is
  # told to swap the sides. Nothing here may change what the simulation reads.
  module SideOneDisplay
    SIDE = 1
    # Battle decisions as the player on side 1 experiences them.
    LOCAL_DECISIONS = { 1 => 2, 2 => 1 }.freeze

    @active = false

    def self.active?
      @active
    end

    def self.mirrors?(link)
      link.side == SIDE
    end

    def self.scene_for(link)
      (mirrors?(link) ? SideOneBattleScene : NetworkBattleScene).new
    end

    # The sprite code reaches the position tables through module functions, so
    # mirroring them needs a flag. It lasts for one battle, even an aborted one.
    def self.during(link)
      @active = mirrors?(link)
      yield
    ensure
      @active = false
    end

    # For the few callers that mean a place on screen rather than a battler.
    def self.unmirrored
      previous = @active
      @active = false
      yield
    ensure
      @active = previous
    end

    def self.screen_index(index)
      @active ? index ^ 1 : index
    end

    # Idempotent, because the scene passes views between its own methods.
    def self.view(battler)
      return battler if !@active || battler.nil? || battler.is_a?(BattlerView)
      BattlerView.new(battler)
    end

    # Forwards everything to the wrapped object.
    class Forwarding
      def initialize(target)
        @target = target
      end

      def method_missing(name, *args, &block)
        @target.respond_to?(name) ? @target.public_send(name, *args, &block) : super
      end

      def respond_to_missing?(name, include_private = false)
        @target.respond_to?(name) || super
      end
    end

    # A battler as the screen places it. "Opposes 0" is how the display code
    # asks "is this a foe?", so 0 stands for the local player's side.
    class BattlerView < Forwarding
      def index
        @target.index ^ 1
      end

      def opposes?(other = 0)
        @target.opposes?(other == 0 ? SIDE : other)
      end
    end

    # The battle as the scene sees it.
    class BattleView < Forwarding
      def is_a?(klass)
        @target.is_a?(klass) || super
      end

      def opposes?(first, second = 0)
        @target.opposes?(first, second == 0 ? SIDE : second)
      end
    end

    module Positions
      def pbBattlerPosition(index, side_size = 1)
        super(SideOneDisplay.screen_index(index), side_size)
      end
    end

    module Metrics
      def apply_metrics_to_sprite(sprite, index, shadow = false)
        super(sprite, SideOneDisplay.screen_index(index), shadow)
      end
    end

    # Draw order of the battler sprites, by place on screen.
    module Depth
      BASE_Z = 50
      Z_STEP = 5

      def pbSetPosition
        super
        return unless SideOneDisplay.active? && @_iconBitmap
        screen = SideOneDisplay.screen_index(@index)
        self.z = screen.even? ? BASE_Z + Z_STEP * screen / 2 : BASE_Z - Z_STEP * (screen + 1) / 2
      end
    end

    module DataBoxView
      def initialize(battler, side_size, viewport = nil)
        super(SideOneDisplay.view(battler), side_size, viewport)
      end

      def battler=(value)
        super(SideOneDisplay.view(value))
      end
    end

    # The slide direction comes from the index that also names the sprite, so
    # the animation gets the on-screen index and finds the box under that name.
    module BoxSlide
      def initialize(sprites, viewport, index)
        return super unless SideOneDisplay.active?
        on_screen = SideOneDisplay.screen_index(index)
        super(sprites.merge("dataBox_#{on_screen}" => sprites["dataBox_#{index}"]), viewport, on_screen)
      end
    end

    # The engine words battlers by comparing their index to 0.
    module BattlerNames
      def pbThis(lower_case = false)
        return super unless @battle.is_a?(NetworkBattle) && @battle.mirrored?
        return name if @index & 1 == SIDE
        lower_case ? _INTL("the opposing {1}", name) : _INTL("The opposing {1}", name)
      end

      def pbTeam(lower_case = false)
        return super unless @battle.is_a?(NetworkBattle) && @battle.mirrored?
        team_name(@index & 1 == SIDE, lower_case)
      end

      def pbOpposingTeam(lower_case = false)
        return super unless @battle.is_a?(NetworkBattle) && @battle.mirrored?
        team_name(@index & 1 != SIDE, lower_case)
      end

      private

      def team_name(local, lower_case)
        return lower_case ? _INTL("your team") : _INTL("Your team") if local
        lower_case ? _INTL("the opposing team") : _INTL("The opposing team")
      end
    end

    # Battle-level messages. Each change lasts only while the engine words one
    # message, so the simulation never observes it.
    module Narration
      def mirrored?
        SideOneDisplay.mirrors?(@link)
      end

      def pbOwnedByPlayer?(index)
        @narrating ? index & 1 == SIDE : super
      end

      def pbThisEx(index, party_index)
        return super unless mirrored?
        name = pbParty(index)[party_index].name
        index & 1 == SIDE ? name : _INTL("The opposing {1}", name)
      end

      def pbMessageOnRecall(battler)
        narrating { super }
      end

      def pbMessagesOnReplace(index, party_index)
        narrating { super }
      end

      # The engine sends out the foe first and says "Go!" for side 0.
      def pbStartBattleSendOut(send_outs)
        return super unless mirrored?
        with_trainers_swapped { super(send_outs.reverse) }
      end

      def pbEndOfBattle
        return super unless mirrored?
        decision = @decision
        begin
          @decision = LOCAL_DECISIONS.fetch(decision, decision)
          with_trainers_swapped { super }
        ensure
          @decision = decision
        end
      end

      private

      def narrating
        previous = @narrating
        @narrating = mirrored?
        yield
      ensure
        @narrating = previous
      end

      def with_trainers_swapped
        @player, @opponent = @opponent, @player
        yield
      ensure
        @player, @opponent = @opponent, @player
      end
    end

    def self.install
      PokeBattle_SceneConstants.singleton_class.prepend(Positions)
      GameData::Species.prepend(Metrics)
      PokemonBattlerSprite.prepend(Depth)
      PokemonDataBox.prepend(DataBoxView)
      [DataBoxAppearAnimation, DataBoxDisappearAnimation].each { |animation| animation.prepend(BoxSlide) }
      PokeBattle_Battler.prepend(BattlerNames)
      NetworkBattle.prepend(Narration)
    end
  end

  # The scene of a duel played from side 1. Sprites stay named by real battler
  # index; only their places on screen are swapped.
  class SideOneBattleScene < NetworkBattleScene
    TARGET_SELECT_MODE = 2

    def pbStartBattle(battle)
      super(SideOneDisplay::BattleView.new(battle))
    end

    # The two bases are scenery: the near one stays near.
    def pbCreateBackdropSprites
      SideOneDisplay.unmirrored { super }
    end

    # The target window lays out and navigates places on screen, so it works
    # in screen indices; the chosen place is turned back into a battler here.
    def pbChooseTarget(idx_battler, target_data, visible_sprites = nil)
      place = super
      place.negative? ? place : SideOneDisplay.screen_index(place)
    end

    def pbCreateTargetTexts(idx_battler, target_data)
      places_of(super)
    end

    def pbFirstTarget(idx_battler, target_data)
      SideOneDisplay.screen_index(super)
    end

    # Mode 2 is the target window's: a place or the names of several places.
    def pbSelectBattler(selected, select_mode = 1)
      return super unless select_mode == TARGET_SELECT_MODE
      super(selected.is_a?(Array) ? places_of(selected) : SideOneDisplay.screen_index(selected), select_mode)
    end

    def pbFindMoveAnimDetails(move2anim, move_id, user_index, hit_number = 0)
      super(move2anim, move_id, SideOneDisplay.screen_index(user_index), hit_number)
    end

    def pbShowAbilitySplash(battler, second_ability = false, ability_name = nil)
      super(SideOneDisplay.view(battler), second_ability, ability_name)
    end

    def pbHideAbilitySplash(battler)
      super(SideOneDisplay.view(battler))
    end

    # The animation takes one side for both the party shown and its place.
    def pbShowPartyLineup(side, full_animation = false)
      @animations.push(LineupAppearAnimation.new(@sprites, @viewport, SideOneDisplay.screen_index(side),
                                                 @battle.pbParty(side), @battle.pbPartyStarts(side), full_animation))
      pbUpdate while !full_animation && inPartyAnimation?
    end

    private

    # Reorders values indexed by battler into values indexed by place, or back.
    def places_of(values)
      Array.new(values.size) { |index| values[index ^ 1] }
    end
  end
end
