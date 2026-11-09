module Multiplayer
  # Converts a party to and from the JSON form sent to the opponent. Received
  # data is untrusted, so decoding validates every field against FIELDS before
  # building anything. Adding a field takes one rule here and one line in each
  # of to_wire and build.
  module PartyCodec
    class InvalidParty < StandardError; end

    PARTY_SIZE = 1..6
    STAT_COUNT = 6..6
    DEX_NUMBERS = 1..501
    MAX_TOTAL_EV = 510
    MAX_NAME_LENGTH = 24
    FALLBACK_NAME = "Pokemon"
    # The engine's JSON writer keeps 6 significant digits, so only integers below
    # 1,000,000 survive. Battles never read the personal ID: what it derives
    # (gender, ability, nature, shininess) is sent separately, and only
    # cosmetics such as Spinda's spots read the bits dropped here.
    PERSONAL_ID_MASK = 0x7FFFF
    SIZE_CATEGORIES = %w[SMALL AVERAGE LARGE SUPER].freeze
    DEFAULT_SIZE_CATEGORY = :AVERAGE
    # Written canonically: FusedSpecies would accept "B073H38" as another id.
    FUSION_ID = /\AB([1-9]\d*)H([1-9]\d*)\z/.freeze
    NAME = /\A[^[:cntrl:]]{1,#{MAX_NAME_LENGTH}}\z/.freeze
    # type_head_body_alt. The game raises on any other sprite type at display.
    SPRITE = /\A(AUTOGEN|CUSTOM|BASE)_(\d{1,4})_(\d{0,4})_([A-Za-z]{0,8})\z/.freeze

    def self.reject(field)
      raise InvalidParty, "invalid party field: #{field}"
    end

    # The game's JSON parser returns every number as a Float.
    def self.whole_number(value)
      return value if value.is_a?(Integer)
      value.to_i if value.is_a?(Float) && value.finite? && value == value.floor
    end

    def self.text(value, field)
      reject(field) unless value.is_a?(String) && value.valid_encoding?
      value
    end

    def self.integer_in(range)
      lambda do |value, field|
        number = whole_number(value)
        reject(field) unless number && range.cover?(number)
        number
      end
    end

    def self.boolean
      lambda do |value, field|
        reject(field) unless value == true || value == false
        value
      end
    end

    def self.optional(rule)
      ->(value, field) { value.nil? ? nil : rule.call(value, field) }
    end

    def self.known_in(data_class)
      lambda do |value, field|
        reject(field) unless data_class.exists?(text(value, field))
        value.to_sym
      end
    end

    def self.one_of(names)
      lambda do |value, field|
        reject(field) unless names.include?(text(value, field))
        value.to_sym
      end
    end

    def self.array_of(sizes, rule)
      lambda do |value, field|
        reject(field) unless value.is_a?(Array) && sizes.cover?(value.length)
        value.each_with_index.map { |element, index| rule.call(element, "#{field}[#{index}]") }
      end
    end

    def self.object_of(rules)
      lambda do |value, field|
        reject(field) unless value.is_a?(Hash) && value.keys.sort_by(&:to_s) == rules.keys.sort
        rules.to_h { |key, rule| [key, rule.call(value[key], "#{field}.#{key}")] }
      end
    end

    def self.species_rule
      lambda do |value, field|
        name = text(value, field)
        fusion = FUSION_ID.match(name)
        # Species.exists? is always true: Species.get falls back to Pikachu.
        known = fusion ? fusion.captures.all? { |part| DEX_NUMBERS.cover?(part.to_i) } : GameData::Species::DATA.key?(name.to_sym)
        reject(field) unless known
        name.to_sym
      end
    end

    def self.ev_rule
      each_stat = array_of(STAT_COUNT, integer_in(0..252))
      lambda do |value, field|
        evs = each_stat.call(value, field)
        reject(field) if evs.sum > MAX_TOTAL_EV
        evs
      end
    end

    def self.name_rule
      lambda do |value, field|
        reject(field) unless text(value, field).match?(NAME)
        value
      end
    end

    # Returns [type, head, body, alt letter], or nil for a malformed sprite.
    def self.parse_sprite(sprite)
      match = SPRITE.match(sprite)
      return nil unless match
      type, head, body, alt_letter = match.captures
      return nil unless DEX_NUMBERS.cover?(head.to_i)
      return nil unless body.empty? ? type == "BASE" : DEX_NUMBERS.cover?(body.to_i)
      [type.to_sym, head.to_i, body.empty? ? nil : body.to_i, alt_letter]
    end

    def self.sprite_rule
      lambda do |value, field|
        parse_sprite(text(value, field)) || reject(field)
      end
    end

    MOVE_FIELDS = {
      "id" => known_in(GameData::Move),
      "pp" => integer_in(0..255),
      "ppup" => integer_in(0..3)
    }.freeze

    FIELDS = {
      "species" => species_rule,
      "level" => integer_in(1..100),
      "form" => integer_in(0..99),
      "personal_id" => integer_in(0..4_294_967_295),
      "gender" => integer_in(0..2),
      "nature" => known_in(GameData::Nature),
      "ability" => optional(known_in(GameData::Ability)),
      "ability_index" => optional(integer_in(0..5)),
      "item" => optional(known_in(GameData::Item)),
      "happiness" => integer_in(0..255),
      "iv" => array_of(STAT_COUNT, integer_in(0..31)),
      "iv_maxed" => array_of(STAT_COUNT, boolean),
      "ev" => ev_rule,
      "moves" => array_of(1..4, object_of(MOVE_FIELDS)),
      "name" => name_rule,
      "shiny" => boolean,
      "head_shiny" => boolean,
      "body_shiny" => boolean,
      "hidden_power_type" => optional(known_in(GameData::Type)),
      "size_category" => optional(one_of(SIZE_CATEGORIES)),
      "pif_sprite" => optional(sprite_rule)
    }.freeze

    PARTY = array_of(PARTY_SIZE, object_of(FIELDS))

    # Raises InvalidParty for eggs, shadow Pokemon, and anything the server
    # would refuse, because the server disconnects on invalid content.
    def self.encode(party)
      party.map { |pokemon| to_wire(pokemon) }.tap { |wire| PARTY.call(wire, "party") }
    end

    def self.decode(wire_party)
      PARTY.call(wire_party, "party").map { |fields| build(fields) }
    end

    def self.main_stat_ids
      ids = []
      GameData::Stat.each_main { |stat| ids << stat.id }
      ids
    end

    # Fainted state and status are left out: duels start at full health.
    def self.to_wire(pokemon)
      raise InvalidParty, "eggs cannot duel" if pokemon.egg?
      raise InvalidParty, "shadow Pokemon cannot duel" if pokemon.shadowPokemon?
      stats = main_stat_ids
      {
        "species" => wire_species(pokemon),
        "level" => pokemon.level,
        "form" => pokemon.form_simple,
        "personal_id" => pokemon.personalID & PERSONAL_ID_MASK,
        "gender" => pokemon.gender,
        "nature" => pokemon.nature.id.to_s,
        "ability" => pokemon.ability_id&.to_s,
        "ability_index" => pokemon.ability_index,
        "item" => pokemon.item_id&.to_s,
        "happiness" => pokemon.happiness,
        "iv" => stats.map { |stat| pokemon.iv[stat] },
        "iv_maxed" => stats.map { |stat| pokemon.ivMaxed[stat] ? true : false },
        "ev" => stats.map { |stat| pokemon.ev[stat] },
        "moves" => pokemon.moves.map { |move| { "id" => move.id.to_s, "pp" => move.pp, "ppup" => move.ppup } },
        "name" => wire_name(pokemon),
        "shiny" => pokemon.shiny? ? true : false,
        "head_shiny" => pokemon.head_shiny ? true : false,
        "body_shiny" => pokemon.body_shiny ? true : false,
        "hidden_power_type" => pokemon.hiddenPowerType&.to_s,
        "size_category" => pokemon.size_category.to_s,
        "pif_sprite" => wire_sprite(pokemon.pif_sprite)
      }
    end

    def self.wire_species(pokemon)
      data = pokemon.species_data
      return pokemon.species.to_s unless data.is_a?(GameData::FusedSpecies)
      "B#{data.body_pokemon.id_number}H#{data.head_pokemon.id_number}"
    end

    def self.wire_name(pokemon)
      cleaned = pokemon.name.to_s.scrub("").gsub(/[[:cntrl:]]/, "")[0, MAX_NAME_LENGTH]
      cleaned.empty? ? FALLBACK_NAME : cleaned
    end

    # A sprite the format cannot carry is omitted: the game then picks its own.
    def self.wire_sprite(sprite)
      return nil unless sprite
      wire = "#{sprite.type}_#{sprite.head_id}_#{sprite.body_id}_#{sprite.alt_letter}"
      parse_sprite(wire) ? wire : nil
    end

    # The owner is neutral so that nothing depends on the local save. Moving a
    # step out of this order changes the result: see each helper.
    def self.build(fields)
      pokemon = Pokemon.new(fields["species"], fields["level"], Pokemon::Owner.new(0, "", 2, 2), false, false)
      apply_identity(pokemon, fields)
      apply_stat_spread(pokemon, fields)
      pokemon.form_simple = fields["form"]
      apply_ability(pokemon, fields)
      pokemon.nature = fields["nature"]
      pokemon.item = fields["item"]
      pokemon.happiness = fields["happiness"]
      pokemon.moves = fields["moves"].map { |move_fields| build_move(move_fields) }
      apply_cosmetics(pokemon, fields)
      # Current HP tracks max HP through every recalculation of a new Pokemon,
      # so this leaves it full. hp= would run the Shields Down form change,
      # which alters the species and writes to the local Pokedex.
      pokemon.calc_stats
      pokemon
    end

    # Pokemon#gender= cannot set 2 and ignores single-gendered species.
    def self.apply_identity(pokemon, fields)
      pokemon.personalID = fields["personal_id"]
      pokemon.instance_variable_set(:@gender, fields["gender"])
      pokemon.size_category = fields["size_category"] || DEFAULT_SIZE_CATEGORY
      pokemon.sprite_scale = pokemon.determine_scale
    end

    def self.apply_stat_spread(pokemon, fields)
      main_stat_ids.each_with_index do |stat, index|
        pokemon.iv[stat] = fields["iv"][index]
        pokemon.ivMaxed[stat] = fields["iv_maxed"][index]
        pokemon.ev[stat] = fields["ev"][index]
      end
    end

    # The constructor already cached an ability, which the index alone would
    # not replace.
    def self.apply_ability(pokemon, fields)
      pokemon.ability_index = fields["ability_index"]
      pokemon.ability = fields["ability"]
    end

    # PP Ups come first because they raise the cap that pp= clamps to.
    def self.build_move(fields)
      move = Pokemon::Move.new(fields["id"])
      move.ppup = fields["ppup"]
      move.pp = fields["pp"]
      move
    end

    # A shiny of nil would be derived from the personal ID and the owner.
    def self.apply_cosmetics(pokemon, fields)
      pokemon.name = fields["name"]
      pokemon.shiny = fields["shiny"]
      pokemon.head_shiny = fields["head_shiny"]
      pokemon.body_shiny = fields["body_shiny"]
      pokemon.hiddenPowerType = fields["hidden_power_type"]
      pokemon.pif_sprite = fields["pif_sprite"] && PIFSprite.new(*fields["pif_sprite"])
    end
  end
end
