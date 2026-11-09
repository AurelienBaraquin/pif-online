module Multiplayer
  # Client side of the duel flow, from the challenge to the start of the battle.
  # Engine-independent: game_hooks/duel displays what this class queues.
  class Duel
    Rules = Struct.new(:party_size, :level, :held_items, :turn_seconds) do
      def to_wire
        { "party_size" => party_size, "level" => level,
          "held_items" => held_items, "turn_seconds" => turn_seconds }
      end
    end
    Invitation = Struct.new(:from, :name, :rules)
    Notice = Struct.new(:kind, :reason, :winner, :link)

    FEATURE_NAME = :duel
    NOTICE_DECLINED = :declined
    NOTICE_ENDED = :ended
    REASON_CONNECTION_LOST = "connection_lost"

    # party_source responds to for_rules(rules) and returns the encoded party.
    def initialize(client, party_source)
      @client = client
      @party_source = party_source
      reset
      client.on_lost { reset }
      client.on("duel_invited") { |data| receive_invitation(data) }
      client.on("duel_declined") { |data| finish_flow(Notice.new(NOTICE_DECLINED, data["reason"], nil)) }
      client.on("duel_accepted") { |_data| send_party }
      client.on("duel_start") { |data| begin_duel(data) }
      client.on("duel_turn") { |data| @link&.receive_turn(data) }
      client.on("duel_replaced") { |data| @link&.receive_replacement(data) }
      client.on("duel_ended") { |data| end_duel(data) }
    end

    def idle?
      @rules.nil? && @invitation.nil? && @link.nil?
    end

    def challenge(target_id, rules)
      return false unless idle? && @client.ready?
      @rules = rules
      @client.deliver("duel_challenge", { "target" => target_id, "rules" => rules.to_wire })
      true
    end

    # Returns the invitation still awaiting an answer, once.
    def take_invitation
      invitation = @invitation
      return nil if invitation.nil? || @invitation_shown
      @invitation_shown = true
      invitation
    end

    def respond(invitation, accept)
      @client.deliver("duel_response", { "from" => invitation.from, "accept" => accept })
      @rules = invitation.rules if accept
      @invitation = nil
      @invitation_shown = false
    end

    def take_notice
      @notices.shift
    end

    # Returns the DuelLink of a duel that just started, once.
    def take_start
      start = @link_to_start
      @link_to_start = nil
      start
    end

    private

    def reset
      @rules = nil
      @invitation = nil
      @invitation_shown = false
      @link&.finish({ "winner" => nil, "reason" => REASON_CONNECTION_LOST })
      @notices = @link_to_start ? [ended_notice(@link_to_start)] : []
      @link = nil
      @link_to_start = nil
    end

    def receive_invitation(data)
      rules = data["rules"]
      @invitation = Invitation.new(data["from"].to_i, data["name"], Rules.new(
        rules["party_size"].to_i, rules["level"].to_i, rules["held_items"], rules["turn_seconds"].to_i
      ))
      @invitation_shown = false
    end

    def send_party
      @client.deliver("duel_party", { "party" => @party_source.for_rules(@rules) })
    end

    def begin_duel(data)
      @link = DuelLink.new(@client, data)
      @link_to_start = @link
    end

    # A duel's outcome goes to its battle; only a duel that never reached the
    # battle needs a notice.
    def end_duel(data)
      link = @link
      @link = nil
      @rules = nil
      link&.finish(data)
      return unless link.nil? || link.equal?(@link_to_start)
      @link_to_start = nil
      finish_flow(link ? ended_notice(link) : Notice.new(NOTICE_ENDED, data["reason"], data["winner"], nil))
    end

    def ended_notice(link)
      Notice.new(NOTICE_ENDED, link.ending.reason, link.ending.winner, link)
    end

    def finish_flow(notice)
      @rules = nil
      @invitation = nil
      @invitation_shown = false
      @notices = @notices + [notice]
    end
  end
end
