module Multiplayer
  # The Multiplayer entry of the pause menu: everything a player needs to choose
  # a server, so no file ever has to be edited by hand.
  module MultiplayerMenu
    Option = Struct.new(:label, :action)

    SITE = "multiplayer.menu"
    ICON = "menuIcons/POKENAV"
    JOIN_TIMEOUT = Connection::CONNECT_TIMEOUT + 2
    MAX_ADDRESS_LENGTH = 64
    ADDRESS_BOX_WIDTH = 320
    OUTCOMES = [Client::STATUS_READY, Client::STATUS_UNREACHABLE, Client::STATUS_REJECTED].freeze

    @incompatible = false

    # Adds the entry just before the last one (Title) and hides the extra
    # position from the game, whose own command indices stay valid.
    module PauseEntry
      def pbShowCommands(commands)
        return super unless MultiplayerMenu.usable?
        position = commands.size - 1
        extended = commands.dup.insert(position, MultiplayerMenu.label)
        loop do
          choice = super(extended)
          return choice > position ? choice - 1 : choice unless choice == position
          pbHideMenu
          MultiplayerMenu.open
          pbShowMenu
        end
      end
    end

    def self.mark_incompatible
      @incompatible = true
    end

    def self.usable?
      !Guard.tripped?(SITE)
    end

    def self.label
      _INTL("  <icon={1}>  Multiplayer", ICON)
    end

    def self.open
      Guard.run(SITE) do
        next pbMessage(_INTL("PIF Online does not support this version of the game.")) if @incompatible
        browse
      end
    end

    def self.browse
      loop do
        entries = options
        labels = entries.map(&:label) + [_INTL("Back")]
        entry = entries[pbMessage(status_text, labels, labels.size)]
        return unless entry
        entry.action.call
      end
    end

    def self.options
      book = Settings.book
      joinable = book.servers.reject { |server| server == book.active && Runtime.running? }
      entries = joinable.map { |server| Option.new(_INTL("Join {1}", server.to_s), -> { join(server) }) }
      entries << Option.new(_INTL("Add a server"), method(:add_server))
      entries << Option.new(_INTL("Remove a server"), method(:remove_server)) unless book.servers.empty?
      entries << Option.new(_INTL("Disconnect"), method(:disconnect)) if Runtime.running?
      entries
    end

    def self.status_text
      server = Settings.book.active
      case Runtime.status
      when Client::STATUS_OFFLINE then _INTL("You are playing offline.")
      when Client::STATUS_READY then _INTL("Connected to {1}.", server.to_s)
      when Client::STATUS_REJECTED then ConnectionPrompts.failure_text(Runtime.status)
      else _INTL("Trying to reach {1}...", server.to_s)
      end
    end

    def self.add_server
      text = pbMessageFreeText(_INTL("Server address (for example 192.168.1.20 or play.example.org):"),
                               "", false, MAX_ADDRESS_LENGTH, ADDRESS_BOX_WIDTH)
      return if text.to_s.strip.empty?
      server = Settings.parse_address(text)
      return pbMessage(_INTL("That address is not valid.")) unless server
      store(Settings.book.add(server))
      join(server)
    end

    def self.remove_server
      servers = Settings.book.servers
      labels = servers.map(&:to_s) + [_INTL("Back")]
      server = servers[pbMessage(_INTL("Remove which server?"), labels, labels.size)]
      return unless server
      if server == Settings.book.active
        return unless can_leave?
        leave
      end
      store(Settings.book.remove(server))
    end

    def self.disconnect
      return unless can_leave?
      leave
      store(Settings.book.with_active(nil))
    end

    def self.join(server)
      return unless can_leave?
      leave
      store(Settings.book.with_active(nil))
      Runtime.start(server, LocalPlayer.name)
      status = await_outcome(server)
      ConnectionPrompts.acknowledge(status)
      report_outcome(server, status)
    end

    def self.report_outcome(server, status)
      if status == Client::STATUS_READY
        store(Settings.book.with_active(server))
        pbMessage(_INTL("Connected to {1}.", server.to_s))
      elsif status == Client::STATUS_OFFLINE
        leave
      else
        text = ConnectionPrompts.failure_text(status)
        leave
        pbMessage(text)
      end
    end

    # Waits on screen for the connection attempt. The Back button cancels it.
    def self.await_outcome(server)
      window = pbCreateMessageWindow
      pbMessageDisplay(window, _INTL("Connecting to {1}...", server.to_s), false)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + JOIN_TIMEOUT
      loop do
        Graphics.update
        Input.update
        pbUpdateSceneMap
        window.update
        return Runtime.status if OUTCOMES.include?(Runtime.status)
        return Client::STATUS_OFFLINE if Input.trigger?(Input::BACK)
        return Client::STATUS_UNREACHABLE if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      end
    ensure
      pbDisposeMessageWindow(window) if window
    end

    def self.can_leave?
      duel = Runtime.feature(Duel::FEATURE_NAME)
      return true if duel.nil? || duel.idle?
      pbMessage(_INTL("Finish your current challenge first."))
      false
    end

    def self.leave
      Runtime.stop
      ConnectionPrompts.acknowledge(Client::STATUS_OFFLINE)
    end

    def self.store(book)
      return if Settings.update(book)
      pbMessage(_INTL("Your server list could not be saved. Check that the game folder is writable."))
    end
  end
end
