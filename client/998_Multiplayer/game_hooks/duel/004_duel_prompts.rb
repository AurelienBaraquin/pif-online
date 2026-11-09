module Multiplayer
  # Shows what the duel flow queued, whenever the game can safely open a message.
  module DuelPrompts
    DECLINE_MESSAGES = {
      "refused" => "The challenge was refused.",
      "busy" => "That player is busy.",
      "offline" => "That player is no longer online.",
      "expired" => "The challenge expired.",
      "game_version" => "That player has a different version of the game, so you cannot duel."
    }.freeze

    def self.update
      duel = Runtime.feature(Duel::FEATURE_NAME)
      return unless duel && can_prompt?
      show_notice(duel) || show_invitation(duel) || begin_duel(duel)
    end

    def self.can_prompt?
      $scene.is_a?(Scene_Map) && !DuelRunner.running && !$game_temp.message_window_showing && !$game_temp.in_menu &&
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
      return DuelRunner.outcome_text(notice.link, notice.link.ending) if notice.link
      return _INTL(DuelRunner::ILLEGAL_TEXT) if notice.reason == Duel::REASON_ILLEGAL
      return _INTL("The duel is over.") if notice.kind == Duel::NOTICE_ENDED
      _INTL(DECLINE_MESSAGES.fetch(notice.reason, "The challenge was cancelled."))
    end

    def self.show_invitation(duel)
      invitation = duel.take_invitation
      return false unless invitation
      enough = DuelParty.available_count >= invitation.rules.party_size
      duel.respond(invitation, enough && confirm_invitation(invitation) && !warn_if_illegal(invitation.rules))
      true
    end

    def self.confirm_invitation(invitation)
      lines = RulesMenu.summary(invitation.rules)
      pbMessage(_INTL("{1} challenges you to a duel!", invitation.name))
      lines[0...-1].each { |line| pbMessage(line) }
      pbConfirmMessage(_INTL("{1} Accept?", lines.last))
    end

    # Tells the player which rule the local team breaks. Returns whether it does.
    def self.warn_if_illegal(rules)
      clause = DuelParty.violation(rules)
      pbMessage(_INTL("Your team breaks the rule: {1}.", _INTL(clause.label))) if clause
      !clause.nil?
    end

    def self.begin_duel(duel)
      link = duel.take_start
      return false unless link
      DuelRunner.run(link)
      true
    end
  end
end
