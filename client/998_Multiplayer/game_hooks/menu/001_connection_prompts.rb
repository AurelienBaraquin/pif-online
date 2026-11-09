module Multiplayer
  # Tells the player when the connection changes without them asking for it.
  module ConnectionPrompts
    REJECTION_TEXTS = {
      "version_mismatch" => "This server runs another version of PIF Online. The server and the game must be updated to the same release.",
      "server_full" => "This server is full. Try again later."
    }.freeze
    REJECTION_FALLBACK = "The server refused the connection."
    UNREACHABLE_TEXT = "Cannot reach the server. Check the address, and that the server is running and open to the network."
    LOST_TEXT = "The connection to the server was lost. Trying to reconnect..."
    RESTORED_TEXT = "Connection to the server restored."
    INTERRUPTED = [Client::STATUS_LOST, Client::STATUS_UNREACHABLE, Client::STATUS_REJECTED].freeze

    @acknowledged = Client::STATUS_OFFLINE

    # The caller already told the player about this status.
    def self.acknowledge(status)
      @acknowledged = status
    end

    def self.update
      status = Runtime.status
      return if status == @acknowledged || !DuelPrompts.can_prompt?
      text = text_for(@acknowledged, status)
      @acknowledged = status
      pbMessage(text) if text
    end

    def self.text_for(previous, status)
      case status
      when Client::STATUS_REJECTED, Client::STATUS_UNREACHABLE then failure_text(status)
      when Client::STATUS_LOST then _INTL(LOST_TEXT)
      when Client::STATUS_READY then INTERRUPTED.include?(previous) ? _INTL(RESTORED_TEXT) : nil
      end
    end

    def self.failure_text(status)
      return _INTL(UNREACHABLE_TEXT) unless status == Client::STATUS_REJECTED
      _INTL(REJECTION_TEXTS.fetch(Runtime.rejection, REJECTION_FALLBACK))
    end
  end
end
