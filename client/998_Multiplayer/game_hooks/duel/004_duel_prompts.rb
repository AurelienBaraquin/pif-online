module Multiplayer
  # Shows what the duel flow queued, whenever the game can safely open a message.
  module DuelPrompts
    DECLINE_MESSAGES = {
      "refused" => "The challenge was refused.",
      "busy" => "That player is busy.",
      "offline" => "That player is no longer online.",
      "expired" => "The challenge expired."
    }.freeze

    def self.update
      duel = Runtime.feature(Duel::FEATURE_NAME)
      return unless duel && can_prompt?
      show_notice(duel) || show_invitation(duel) || begin_duel(duel)
    end

    def self.can_prompt?
      $scene.is_a?(Scene_Map) && !$game_temp.message_window_showing && !$game_temp.in_menu &&
        !$game_temp.in_battle && !$game_temp.player_transferring &&
        !pbMapInterpreterRunning? && !$game_player.moving?
    end

    def self.show_notice(duel)
      notice = duel.take_notice
      return false unless notice
      pbMessage(notice_text(notice))
      true
    end

    def self.notice_text(notice)
      return _INTL("The duel is over.") if notice.kind == Duel::NOTICE_ENDED
      _INTL(DECLINE_MESSAGES.fetch(notice.reason, "The challenge was cancelled."))
    end

    def self.show_invitation(duel)
      invitation = duel.take_invitation
      return false unless invitation
      enough = DuelParty.available_count >= invitation.rules.party_size
      duel.respond(invitation, enough && confirm_invitation(invitation))
      true
    end

    def self.confirm_invitation(invitation)
      pbConfirmMessage(_INTL("{1} challenges you to a duel! {2} Accept?",
                             invitation.name, RulesMenu.summary(invitation.rules)))
    end

    def self.begin_duel(duel)
      link = duel.take_start
      return false unless link
      DuelRunner.run(link)
      true
    end
  end
end
