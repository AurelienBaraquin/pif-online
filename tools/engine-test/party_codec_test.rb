# Checks that a party survives the trip over the network: every battle-relevant
# attribute is preserved, a rebuilt party simulates like the original, and
# malformed data is refused before anything is built. Reuses the duel harness
# of battle_determinism_test.rb, which is staged and loaded before this file.

module PartyCodecTest
  RESULT_FILE = BattleDeterminism::RESULT_FILE
  ROUND_TRIPS = 200
  SIMULATION_BUDGET = 60
  MAX_LINE_BYTES = 16 * 1024
  ROSTER_DEX = 1..251
  FUSION_CHANCE = 50
  SIZES = %i[SMALL AVERAGE LARGE SUPER].freeze
  SPRITES = [nil, [:CUSTOM, 38, 73, "a"], [:AUTOGEN, 38, 73, ""], [:BASE, 25, nil, "b"]].freeze
  Codec = Multiplayer::PartyCodec

  # Counts constructions, to prove that invalid data builds nothing.
  module BuildCounter
    @count = 0

    class << self
      attr_accessor :count
    end

    def new(*args)
      BuildCounter.count += 1
      super
    end
  end

  @failures = []

  def self.report(line)
    File.open(RESULT_FILE, "a") { |file| file.puts(line) }
  end

  def self.check(condition, label)
    @failures << label unless condition
  end

  def self.network(value)
    HTTPLite::JSON.parse(HTTPLite::JSON.stringify(value))
  end

  def self.random_species(rng)
    head = rng.rand(ROSTER_DEX)
    return head if rng.rand(100) >= FUSION_CHANCE
    getFusionSpecies(rng.rand(ROSTER_DEX), head).id
  end

  def self.random_stat_spread(pokemon, rng)
    budget = Pokemon::EV_LIMIT
    GameData::Stat.each_main do |stat|
      pokemon.iv[stat.id] = rng.rand(32)
      pokemon.ivMaxed[stat.id] = rng.rand(4).zero?
      pokemon.ev[stat.id] = rng.rand(0..[budget, Pokemon::EV_STAT_LIMIT].min)
      budget -= pokemon.ev[stat.id]
    end
  end

  def self.random_moves(pokemon, rng, move_ids)
    pokemon.moves.clear
    move_ids.sample(rng.rand(1..4), random: rng).each { |move| pokemon.learn_move(move) }
    pokemon.moves.each do |move|
      move.ppup = rng.rand(4)
      move.pp = rng.rand(0..move.total_pp)
    end
  end

  def self.random_ability(pokemon, rng)
    pokemon.ability_index = rng.rand(3)
    choices = pokemon.getAbilityList
    pokemon.ability = choices.sample(random: rng)[0] unless choices.empty?
  end

  # The game derives the scale from the category when it creates a Pokemon.
  def self.apply_size(pokemon, size)
    pokemon.size_category = size
    pokemon.sprite_scale = pokemon.determine_scale
  end

  def self.random_cosmetics(pokemon, rng)
    pokemon.name = ["", "Zoé", "Fusion_Nick"].sample(random: rng)
    pokemon.shiny = rng.rand(2).zero?
    pokemon.head_shiny = rng.rand(2).zero?
    pokemon.body_shiny = rng.rand(2).zero?
    pokemon.hiddenPowerType = [nil, :FIRE, :ICE].sample(random: rng)
    apply_size(pokemon, SIZES.sample(random: rng))
    sprite = SPRITES.sample(random: rng)
    pokemon.pif_sprite = sprite && PIFSprite.new(sprite[0], sprite[1], sprite[2], sprite[3].to_s)
  end

  def self.random_pokemon(rng, move_ids, species = random_species(rng))
    pokemon = Pokemon.new(species, rng.rand(1..100))
    pokemon.personalID = rng.rand(1 << 32)
    pokemon.instance_variable_set(:@gender, rng.rand(3))
    pokemon.form_simple = rng.rand(3)
    random_stat_spread(pokemon, rng)
    random_ability(pokemon, rng)
    pokemon.nature = GameData::Nature.keys.grep(Symbol).sample(random: rng)
    pokemon.item = BattleDeterminism::HELD_ITEMS.sample(random: rng)
    pokemon.happiness = rng.rand(256)
    random_moves(pokemon, rng, move_ids)
    random_cosmetics(pokemon, rng)
    pokemon.calc_stats
    pokemon
  end

  def self.battle_view(pokemon)
    sprite = pokemon.pif_sprite
    [pokemon.species, pokemon.level, pokemon.form_simple, pokemon.personalID & Codec::PERSONAL_ID_MASK, pokemon.gender,
     pokemon.nature.id, pokemon.ability_id, pokemon.ability_index, pokemon.item_id, pokemon.happiness,
     pokemon.iv, pokemon.ivMaxed.transform_values { |maxed| maxed ? true : false }, pokemon.ev,
     pokemon.moves.map { |move| [move.id, move.pp, move.ppup] }, pokemon.name,
     pokemon.shiny? ? true : false, pokemon.head_shiny ? true : false, pokemon.body_shiny ? true : false,
     pokemon.hiddenPowerType, pokemon.size_category, pokemon.sprite_scale,
     pokemon.type1, pokemon.type2, pokemon.totalhp, pokemon.hp, pokemon.attack, pokemon.defense,
     pokemon.spatk, pokemon.spdef, pokemon.speed, pokemon.status, pokemon.statusCount,
     sprite && [sprite.type, sprite.head_id, sprite.body_id, sprite.alt_letter]]
  end

  def self.check_round_trip(original, label)
    wire = network(Codec.encode([original]))
    rebuilt = Codec.decode(wire).first
    view = battle_view(original)
    rebuilt_view = battle_view(rebuilt)
    difference = (0...view.size).find { |i| view[i] != rebuilt_view[i] }
    check(difference.nil?, "#{label}: field #{difference}: #{view[difference || 0].inspect} != #{rebuilt_view[difference || 0].inspect}")
    check(rebuilt.hp == rebuilt.totalhp, "#{label}: not at full health")
    check(rebuilt.owner.id.zero? && rebuilt.owner.name.empty?, "#{label}: owner depends on the save")
  end

  def self.test_round_trips(move_ids)
    rng = Random.new(1)
    ROUND_TRIPS.times do |index|
      original = random_pokemon(rng, move_ids)
      check_round_trip(original, "round trip #{index} #{original.species}")
    end
    check(network(1).is_a?(Float), "JSON parser no longer returns Float: adjust whole_number")
    largest_id = Codec::PERSONAL_ID_MASK
    check(HTTPLite::JSON.stringify(largest_id) == largest_id.to_s, "largest personal_id is not written exactly")
    full_party = Array.new(6) { random_pokemon(rng, move_ids) }
    line = HTTPLite::JSON.stringify(Codec.encode(full_party))
    check(line.bytesize < MAX_LINE_BYTES, "full party takes #{line.bytesize} bytes")
  end

  def self.special_case(rng, move_ids, species, label)
    pokemon = random_pokemon(rng, move_ids, species)
    yield pokemon
    pokemon.calc_stats
    check_round_trip(pokemon, label)
  end

  def self.test_special_cases(move_ids)
    rng = Random.new(2)
    special_case(rng, move_ids, :SHEDINJA, "Wonder Guard") { |p| p.ability = :WONDERGUARD }
    SIZES.each do |size|
      special_case(rng, move_ids, :PUMPKABOO, "size #{size}") { |p| apply_size(p, size) }
    end
    special_case(rng, move_ids, :PIKACHU, "hidden power") { |p| p.hiddenPowerType = :WATER }
    return unless GameData::Species::DATA.key?(:MINIOR_C)
    # Writing HP on this one would turn it into the other Minior.
    fusion = getFusionSpecies(GameData::Species.get(:MINIOR_C).id_number, 25).id
    special_case(rng, move_ids, fusion, "Shields Down fusion") { |p| p.ability = :SHIELDSDOWN }
  end

  def self.test_encode_refusals(move_ids)
    rng = Random.new(3)
    egg = random_pokemon(rng, move_ids)
    egg.steps_to_hatch = 10
    shadow = random_pokemon(rng, move_ids)
    shadow.instance_variable_set(:@shadow, true)
    shadow.instance_variable_set(:@heart_gauge, 100)
    check_refused("encode egg") { Codec.encode([egg]) }
    check_refused("encode shadow") { Codec.encode([shadow]) }
  end

  def self.check_refused(label)
    yield
    @failures << "#{label}: accepted"
  rescue Codec::InvalidParty
    nil
  rescue *Multiplayer::Guard::RECOVERABLE => e
    @failures << "#{label}: raised #{e.class}: #{e.message}"
  end

  def self.mutations
    {
      "unknown species" => ->(p) { p["species"] = "NOTAPOKEMON" },
      "fusion part 999" => ->(p) { p["species"] = "B999H1" },
      "fusion part 0" => ->(p) { p["species"] = "B0H1" },
      "fusion leading zero" => ->(p) { p["species"] = "B073H38" },
      "new format fusion" => ->(p) { p["species"] = "1/2" },
      "species number" => ->(p) { p["species"] = 25 },
      "invalid encoding" => ->(p) { p["species"] = "\xFF" },
      "level 0" => ->(p) { p["level"] = 0 },
      "level 101" => ->(p) { p["level"] = 101 },
      "fractional level" => ->(p) { p["level"] = 5.5 },
      "level string" => ->(p) { p["level"] = "5" },
      "infinite level" => ->(p) { p["level"] = Float::INFINITY },
      "form 100" => ->(p) { p["form"] = 100 },
      "personal id too large" => ->(p) { p["personal_id"] = 4_294_967_296 },
      "gender 3" => ->(p) { p["gender"] = 3 },
      "unknown nature" => ->(p) { p["nature"] = "GRUMPY" },
      "unknown ability" => ->(p) { p["ability"] = "HACKING" },
      "ability index 6" => ->(p) { p["ability_index"] = 6 },
      "unknown item" => ->(p) { p["item"] = "EXPLOIT" },
      "happiness 256" => ->(p) { p["happiness"] = 256 },
      "iv 32" => ->(p) { p["iv"][0] = 32 },
      "five ivs" => ->(p) { p["iv"].pop },
      "iv_maxed number" => ->(p) { p["iv_maxed"][0] = 1 },
      "ev 253" => ->(p) { p["ev"] = [253, 0, 0, 0, 0, 0] },
      "ev total above 510" => ->(p) { p["ev"] = [252, 252, 7, 0, 0, 0] },
      "no moves" => ->(p) { p["moves"] = [] },
      "five moves" => ->(p) { p["moves"] = [p["moves"][0]] * 5 },
      "unknown move" => ->(p) { p["moves"][0]["id"] = "NUKE" },
      "pp 256" => ->(p) { p["moves"][0]["pp"] = 256 },
      "ppup 4" => ->(p) { p["moves"][0]["ppup"] = 4 },
      "move not an object" => ->(p) { p["moves"][0] = "TACKLE" },
      "empty name" => ->(p) { p["name"] = "" },
      "name too long" => ->(p) { p["name"] = "x" * 25 },
      "name with newline" => ->(p) { p["name"] = "a\nb" },
      "shiny number" => ->(p) { p["shiny"] = 1 },
      "head_shiny null" => ->(p) { p["head_shiny"] = nil },
      "unknown hidden power" => ->(p) { p["hidden_power_type"] = "DOOM" },
      "unknown size" => ->(p) { p["size_category"] = "COLOSSAL" },
      "sprite path traversal" => ->(p) { p["pif_sprite"] = "../../Game.ini" },
      "sprite with slash" => ->(p) { p["pif_sprite"] = "CUSTOM/38_73_a" },
      "sprite too long" => ->(p) { p["pif_sprite"] = "a" * 65 },
      "sprite unknown type" => ->(p) { p["pif_sprite"] = "TRIPLE_38_73_a" },
      "sprite fusion without body" => ->(p) { p["pif_sprite"] = "CUSTOM_38__a" },
      "sprite dex 999" => ->(p) { p["pif_sprite"] = "BASE_999__" },
      "missing field" => ->(p) { p.delete("nature") },
      "extra field" => ->(p) { p["status"] = "SLEEP" }
    }
  end

  def self.test_rejections(move_ids)
    valid = network(Codec.encode([random_pokemon(Random.new(4), move_ids)])).first
    Codec.decode([valid])
    mutations.each do |label, mutation|
      broken = network(valid)
      mutation.call(broken)
      check_refused(label) { Codec.decode([broken]) }
    end
    check_refused("not an array") { Codec.decode(valid) }
    check_refused("nil party") { Codec.decode(nil) }
    check_refused("empty party") { Codec.decode([]) }
    check_refused("seven Pokemon") { Codec.decode([valid] * 7) }
    check_refused("Pokemon not an object") { Codec.decode([1]) }
    test_nothing_built_when_invalid(valid)
  end

  def self.test_nothing_built_when_invalid(valid)
    broken = network(valid)
    broken["ev"] = [252, 252, 252, 0, 0, 0]
    BuildCounter.count = 0
    check_refused("last Pokemon invalid") { Codec.decode([valid, valid, broken]) }
    check(BuildCounter.count.zero?, "built #{BuildCounter.count} Pokemon from an invalid party")
  end

  # A duel the original party cannot finish says nothing about the codec.
  def self.simulate_original(parties, seed, script)
    BattleDeterminism.play(parties, seed, BattleDeterminism::VARIANTS[0], script, Random.new(seed * 7))
  rescue *Multiplayer::Guard::RECOVERABLE
    nil
  end

  def self.test_simulations(move_ids)
    baseline = BattleDeterminism::VARIANTS[0]
    deadline = BattleDeterminism.now + SIMULATION_BUDGET
    BattleDeterminism.start_watchdog
    seed = duels = 0
    while BattleDeterminism.now < deadline
      seed += 1
      BattleDeterminism.touch
      rng = Random.new(seed)
      parties = Array.new(2) { Array.new(6) { random_pokemon(rng, move_ids) } }
      parties.each { |party| party.each(&:heal) }
      script = { 0 => [], 1 => [] }
      reference = simulate_original(parties, seed, script)
      next unless reference
      rebuilt = parties.map { |party| Codec.decode(network(Codec.encode(party))) }
      trace = BattleDeterminism.play(rebuilt, seed, baseline, script.transform_values(&:dup), nil)
      difference = BattleDeterminism.compare(reference, trace)
      check(difference.nil?, "duel #{seed} diverged: #{difference.inspect[0, 300]}")
      duels += 1
      Graphics.update
    end
    report("simulated duels=#{duels} attempts=#{seed}")
    check(duels > 0, "no duel could be simulated")
  end

  def self.run
    File.delete(RESULT_FILE) if File.exist?(RESULT_FILE)
    report("started")
    Pokemon.singleton_class.prepend(BuildCounter)
    move_ids = GameData::Move.keys.select { |id| id.is_a?(Symbol) }
    test_round_trips(move_ids)
    test_special_cases(move_ids)
    test_encode_refusals(move_ids)
    test_rejections(move_ids)
    test_simulations(move_ids)
    @failures.first(20).each { |failure| report(failure) }
    report(@failures.empty? ? "PASS" : "FAIL #{@failures.size} checks")
  rescue Exception => e
    report("FAIL #{e.class}: #{e.message}\n#{(e.backtrace || []).first(8).join("\n")}")
  ensure
    exit
  end
end

class Scene_Intro
  def main
    Game.start_new
    PartyCodecTest.run
  end
end
