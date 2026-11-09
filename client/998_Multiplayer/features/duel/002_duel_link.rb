module Multiplayer
  # The network side of one started duel: what the battle sends and awaits.
  # Engine-independent, and fed by Duel as messages arrive.
  class DuelLink
    Ending = Struct.new(:winner, :reason)
    Choice = Struct.new(:action, :index)

    attr_reader :seed, :side, :rules, :players, :parties, :ending

    def initialize(client, start)
      @client = client
      @seed = start["seed"].to_i
      @side = start["side"].to_i
      @rules = start["rules"]
      @players = start["players"]
      @parties = start["parties"]
      @turns = {}
      @replacements = { 0 => [], 1 => [] }
      @next_seq = 0
      @ending = nil
    end

    def send_choice(round, choice)
      @client.deliver("duel_choice", { "round" => round, "action" => choice.action, "index" => choice.index })
    end

    def send_replacement(index)
      @client.deliver("duel_replacement", { "seq" => @next_seq, "index" => index })
      @next_seq += 1
    end

    def send_hash(round, hash)
      @client.deliver("duel_hash", { "round" => round, "hash" => hash })
    end

    def send_result(winner)
      @client.deliver("duel_result", { "winner" => winner })
    end

    def forfeit
      @client.deliver("duel_forfeit", nil)
    end

    # Returns both choices of a round in side order, or nil until they arrive.
    def turn(round)
      @turns[round]
    end

    # Returns the next replacement of a side, or nil until it arrives.
    def next_replacement(side)
      @replacements[side].shift
    end

    def receive_turn(data)
      @turns[data["round"].to_i] = data["choices"].map { |choice| parse_choice(choice) }
    end

    def receive_replacement(data)
      @replacements[data["side"].to_i] << data["index"].to_i
    end

    def finish(data)
      winner = data["winner"]
      @ending = Ending.new(winner&.to_i, data["reason"])
    end

    private

    def parse_choice(data)
      Choice.new(data["action"], data["index"].to_i)
    end
  end
end
