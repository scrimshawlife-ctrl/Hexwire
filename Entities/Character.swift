import Foundation

// MARK: - Enums

enum CharacterArchetype: String, Codable, CaseIterable {
    case streetSam   = "Street Samurai"
    case mage        = "Mage"
    case decker      = "Decker"
    case face        = "Face"

    var description: String {
        switch self {
        case .streetSam: return "High BOD/AGI, melee and firearms expert"
        case .mage:      return "High MAG/WIL, spellcaster with mana pool"
        case .decker:    return "High LOG/INT, social engineering specialist"
        case .face:      return "High CHA/AGI, social encounters and ranged backup"
        }
    }
}

enum AttributeKey: String, Codable, CaseIterable {
    case bod  // Body
    case agi  // Agility
    case rea  // Reaction
    case str  // Strength
    case cha  // Charisma
    case int  // Intuition
    case log  // Logic
    case wil  // Willpower
}

enum SkillKey: String, Codable, CaseIterable {
    case firearms
    case blades
    case unarmed
    case perception
    case sneaking
    case conjuring
    case spellcasting
}

// MARK: - Attribute Set

struct AttributeSet: Codable, Equatable {
    var bod: Int
    var agi: Int
    var rea: Int
    var str: Int
    var cha: Int
    var int: Int
    var log: Int
    var wil: Int

    static let zero = AttributeSet(bod: 0, agi: 0, rea: 0, str: 0, cha: 0, int: 0, log: 0, wil: 0)

    subscript(key: AttributeKey) -> Int {
        get {
            switch key {
            case .bod: return bod
            case .agi: return agi
            case .rea: return rea
            case .str: return str
            case .cha: return cha
            case .int: return int
            case .log: return log
            case .wil: return wil
            }
        }
        set {
            switch key {
            case .bod: bod = newValue
            case .agi: agi = newValue
            case .rea: rea = newValue
            case .str: str = newValue
            case .cha: cha = newValue
            case .int: int = newValue
            case .log: log = newValue
            case .wil: wil = newValue
            }
        }
    }
}

// MARK: - Skill Set

struct SkillSet: Codable, Equatable {
    var firearms: Int
    var blades: Int
    var unarmed: Int
    var perception: Int
    var sneaking: Int
    var conjuring: Int
    var spellcasting: Int

    static let zero = SkillSet(firearms: 0, blades: 0, unarmed: 0, perception: 0, sneaking: 0, conjuring: 0, spellcasting: 0)

    subscript(key: SkillKey) -> Int {
        get {
            switch key {
            case .firearms:   return firearms
            case .blades:     return blades
            case .unarmed:    return unarmed
            case .perception: return perception
            case .sneaking:   return sneaking
            case .conjuring:  return conjuring
            case .spellcasting: return spellcasting
            }
        }
        set {
            switch key {
            case .firearms:   firearms = newValue
            case .blades:     blades = newValue
            case .unarmed:    unarmed = newValue
            case .perception: perception = newValue
            case .sneaking:   sneaking = newValue
            case .conjuring:  conjuring = newValue
            case .spellcasting: spellcasting = newValue
            }
        }
    }
}

// MARK: - Derived Stats

struct DerivedStats {
    let initiative: Int
    let soak: Int
    let spellDefense: Int

    static let zero = DerivedStats(initiative: 0, soak: 0, spellDefense: 0)
}

// MARK: - Status Effect

enum StatusEffect: Codable, Equatable {
    case prone
    case stunned
    case wounded
    case dead
    case burning(roundsLeft: Int)
    case marked(roundsLeft: Int)
    case confused(roundsLeft: Int)

    var displayName: String {
        switch self {
        case .prone:              return "Prone"
        case .stunned:            return "Stunned"
        case .wounded:            return "Wounded"
        case .dead:               return "Dead"
        case .burning(let r):     return "Burning·\(r)"
        case .marked(let r):      return "Marked·\(r)"
        case .confused(let r):    return "Confused·\(r)"
        }
    }
}

// MARK: - Character

final class Character: ObservableObject, Identifiable, Codable {
    let id: UUID
    var name: String
    var archetype: CharacterArchetype

    @Published var attributes: AttributeSet
    @Published var skills: SkillSet

    // Gear
    @Published var equippedWeapon: Weapon?
    @Published var equippedArmor: Armor?
    @Published var inventory: [Item]

    // Combat state — Physical damage track (BOD/2+8 rounded up)
    @Published var currentHP: Int
    var maxHP: Int

    // Stun damage track (WIL/2+8 rounded up). Overflow goes to physical.
    @Published var currentStun: Int = 0
    var maxStun: Int { Int(ceil(Double(attributes.wil) / 2.0)) + 8 }

    @Published var currentMana: Int   // mage only
    let maxMana: Int

    // Position
    @Published var positionX: Int = 0
    @Published var positionY: Int = 0

    // Status
    @Published var status: StatusEffect = .wounded
    /// Active timed status effects — burning, marked, confused, etc.
    /// These are checked/ticked at the start of each round alongside the legacy single `status`.
    @Published var statusEffects: [StatusEffect] = []

    // Per-round action tracking — set true after ANY combat action; reset at round start.
    @Published var hasActedThisRound: Bool = false

    /// How many BLITZ charges the runner has burned this mission. Capped by
    /// `blitzChargesPerMission` (currently `4 + level`, so level 1 = 5, lvl 2
    /// = 6, etc.). Reset to 0 in MissionSetupService.setupMission.
    /// Only meaningful for Street Samurai but stored on every Character to
    /// keep the model uniform.
    @Published var blitzChargesUsed: Int = 0
    var blitzChargesPerMission: Int { max(1, 4 + level) }
    var blitzChargesRemaining: Int { max(0, blitzChargesPerMission - blitzChargesUsed) }

    // Cyberware / spells
    var cyberware: [String] = []
    var spells: [String] = []

    // Initiative
    var initiativeRoll: Int = 0

    // MARK: - Leveling
    @Published var level: Int = 1
    @Published var xp: Int = 0

    var xpForNextLevel: Int { level * 50 }

    func gainXP(_ amount: Int) -> Bool {
        xp += amount
        if xp >= xpForNextLevel {
            xp -= xpForNextLevel
            level += 1
            // HP gain on level up
            maxHP += 3
            currentHP = min(currentHP + 3, maxHP)
            // Archetype-specific stat improvements
            switch archetype {
            case .streetSam:
                attributes.bod = min(8, attributes.bod + 1)
                attributes.agi = min(8, attributes.agi + 1)
                skills.blades = min(8, skills.blades + 1)
            case .mage:
                attributes.log = min(8, attributes.log + 1)
                attributes.wil = min(8, attributes.wil + 1)
                skills.spellcasting = min(8, skills.spellcasting + 1)
                currentMana = min(currentMana + 2, maxMana)
            case .decker:
                attributes.int = min(8, attributes.int + 1)
                attributes.log = min(8, attributes.log + 1)
                skills.perception = min(8, skills.perception + 1)
            case .face:
                attributes.agi = min(8, attributes.agi + 1)
                attributes.cha = min(8, attributes.cha + 1)
                skills.firearms = min(8, skills.firearms + 1)
            }
            return true
        }
        return false
    }

    enum CodingKeys: String, CodingKey {
        case id, name, archetype, attributes, skills
        case equippedWeapon, equippedArmor, inventory
        case currentHP, maxHP, currentStun, currentMana, maxMana
        case positionX, positionY, status, statusEffects
        case cyberware, spells, level, xp
        case hasActedThisRound
    }

    init(id: UUID = UUID(), name: String, archetype: CharacterArchetype,
         attributes: AttributeSet, skills: SkillSet,
         weapon: Weapon? = nil, armor: Armor? = nil,
         maxHP: Int, maxMana: Int = 0) {
        self.id = id
        self.name = name
        self.archetype = archetype
        self.attributes = attributes
        self.skills = skills
        self.equippedWeapon = weapon
        self.equippedArmor = armor
        self.inventory = []
        self.currentHP = maxHP
        self.maxHP = maxHP
        self.currentMana = maxMana
        self.maxMana = maxMana
    }

    // Codable
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        archetype = try container.decode(CharacterArchetype.self, forKey: .archetype)
        attributes = try container.decode(AttributeSet.self, forKey: .attributes)
        skills = try container.decode(SkillSet.self, forKey: .skills)
        equippedWeapon = try container.decodeIfPresent(Weapon.self, forKey: .equippedWeapon)
        equippedArmor = try container.decodeIfPresent(Armor.self, forKey: .equippedArmor)
        inventory = try container.decode([Item].self, forKey: .inventory)
        currentHP = try container.decode(Int.self, forKey: .currentHP)
        maxHP = try container.decode(Int.self, forKey: .maxHP)
        currentStun = try container.decodeIfPresent(Int.self, forKey: .currentStun) ?? 0
        currentMana = try container.decode(Int.self, forKey: .currentMana)
        maxMana = try container.decode(Int.self, forKey: .maxMana)
        positionX = try container.decode(Int.self, forKey: .positionX)
        positionY = try container.decode(Int.self, forKey: .positionY)
        status = try container.decode(StatusEffect.self, forKey: .status)
        statusEffects = try container.decodeIfPresent([StatusEffect].self, forKey: .statusEffects) ?? []
        cyberware = try container.decodeIfPresent([String].self, forKey: .cyberware) ?? []
        spells = try container.decodeIfPresent([String].self, forKey: .spells) ?? []
        level = try container.decodeIfPresent(Int.self, forKey: .level) ?? 1
        xp = try container.decodeIfPresent(Int.self, forKey: .xp) ?? 0
        hasActedThisRound = try container.decodeIfPresent(Bool.self, forKey: .hasActedThisRound) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(archetype, forKey: .archetype)
        try container.encode(attributes, forKey: .attributes)
        try container.encode(skills, forKey: .skills)
        try container.encode(equippedWeapon, forKey: .equippedWeapon)
        try container.encode(equippedArmor, forKey: .equippedArmor)
        try container.encode(inventory, forKey: .inventory)
        try container.encode(currentHP, forKey: .currentHP)
        try container.encode(maxHP, forKey: .maxHP)
        try container.encode(currentStun, forKey: .currentStun)
        try container.encode(currentMana, forKey: .currentMana)
        try container.encode(maxMana, forKey: .maxMana)
        try container.encode(positionX, forKey: .positionX)
        try container.encode(positionY, forKey: .positionY)
        try container.encode(status, forKey: .status)
        try container.encode(statusEffects, forKey: .statusEffects)
        try container.encode(cyberware, forKey: .cyberware)
        try container.encode(spells, forKey: .spells)
        try container.encode(level, forKey: .level)
        try container.encode(xp, forKey: .xp)
        try container.encode(hasActedThisRound, forKey: .hasActedThisRound)
    }

    // MARK: - Derived Stats

    func computeDerived() -> DerivedStats {
        let armorValue = equippedArmor?.armorValue ?? 0
        let soak = attributes.bod + armorValue
        let spellDefense = attributes.wil + attributes.bod
        let initiative = attributes.rea + attributes.int  // + 1d6 rolled separately
        return DerivedStats(initiative: initiative, soak: soak, spellDefense: spellDefense)
    }

    // MARK: - Combat Pool

    /// Dice pool for an attack using a given skill
    func attackPool(skill: SkillKey) -> Int {
        return attributes[skillToAttr(skill)] + skills[skill]
    }

    /// Dice pool for a defense (dodge/parry)
    func defensePool() -> Int {
        return attributes.rea + attributes.agi
    }

    private func skillToAttr(_ skill: SkillKey) -> AttributeKey {
        // AGI-based skills
        switch skill {
        case .firearms, .blades, .unarmed, .sneaking:
            return .agi
        case .perception:
            return .int
        case .conjuring, .spellcasting:
            return .log
        }
    }

    // MARK: - Status

    var isAlive: Bool {
        status != .dead && currentHP > 0
    }

    var hpPercent: Double {
        guard maxHP > 0 else { return 0 }
        return Double(currentHP) / Double(maxHP)
    }

    var manaPercent: Double {
        guard maxMana > 0 else { return 0 }
        return Double(currentMana) / Double(maxMana)
    }

    // MARK: - Heal/ Damage

    func heal(amount: Int) {
        currentHP = min(maxHP, currentHP + amount)
    }

    /// Apply damage. isStun=true uses the Stun track (WIL-based); overflow goes to Physical.
    func takeDamage(amount: Int, isStun: Bool = false) {
        if isStun {
            let stunSpace = max(0, maxStun - currentStun)
            let stunApplied = min(amount, stunSpace)
            let overflow = amount - stunApplied
            currentStun += stunApplied
            if overflow > 0 {
                currentHP = max(0, currentHP - overflow)
            }
        } else {
            currentHP = max(0, currentHP - amount)
        }
        if currentHP <= 0 {
            status = .dead
        } else if currentStun >= maxStun {
            status = .stunned  // fully stunned but not dead yet
        }
    }

    /// Recover stun damage (rest, healing, etc.)
    func recoverStun(amount: Int) {
        currentStun = max(0, currentStun - amount)
        if status == .stunned && currentStun < maxStun { status = .wounded }
    }
}

// MARK: - Pre-built Characters

extension Character {

    /// Street Samurai: high BOD/AGI, melee + firearms
    static func streetSam() -> Character {
        var attrs = AttributeSet.zero
        attrs.bod = 5
        attrs.agi = 5
        attrs.rea = 4
        attrs.str = 4
        attrs.cha = 2
        attrs.int = 3
        attrs.log = 2
        attrs.wil = 3

        var skills = SkillSet.zero
        skills.blades = 4
        skills.firearms = 4
        skills.unarmed = 2
        skills.perception = 2
        skills.sneaking = 2

        let weapon = Weapon(name: "Katana", type: .blade, damage: 8, accuracy: 6, armorPiercing: 2)
        let armor = Armor(name: "Medium Armor", armorValue: 4, spellPenalty: -1)

        let character = Character(
            name: "Raze",
            archetype: .streetSam,
            attributes: attrs,
            skills: skills,
            weapon: weapon,
            armor: armor,
            maxHP: 18
        )
        character.cyberware = ["Syntheskin", "Reflex Boosters"]
        return character
    }

    /// Mage: high MAG/WIL, spellcasting + conjuring
    static func mage() -> Character {
        var attrs = AttributeSet.zero
        attrs.bod = 3
        attrs.agi = 3
        attrs.rea = 3
        attrs.str = 2
        attrs.cha = 3
        attrs.int = 4
        attrs.log = 5
        attrs.wil = 5

        var skills = SkillSet.zero
        skills.spellcasting = 5
        skills.conjuring = 4
        skills.perception = 2
        // Bumped 2026-05 (was 1) — at 1 Sable's sidearm rolled a 5-die
        // pool that glitched (1 in 5) more than it landed solid hits. At 3
        // her sidearm pool reaches 7 dice, putting it on the same usable
        // tier as a backup weapon should be (still clearly secondary to
        // her spells).
        skills.firearms = 3
        // Bumped 2026-05 (was 0) — Stunball uses the .unarmed skill in the
        // attack-pool lookup, so leaving this at 0 gave Sable a 3-die pool
        // that essentially never landed against any enemy. With 4 the Mage
        // can actually land her ranged spell-equivalent.
        skills.unarmed = 4

        let weapon = Weapon(name: "Stunball", type: .unarmed, damage: 6, accuracy: 4, armorPiercing: 0)
        let armor = Armor(name: "Light Armor", armorValue: 2, spellPenalty: 0)

        let character = Character(
            name: "Sable",
            archetype: .mage,
            attributes: attrs,
            skills: skills,
            weapon: weapon,
            armor: armor,
            maxHP: 14,
            maxMana: 10
        )
        character.spells = ["Firestorm", "Confusion", "Increase Attribute"]
        return character
    }

    /// Decker: high LOG/INT, social engineering. 2026-05-14 weapon swap —
    /// monoblade primary so the party has two melee threats instead of
    /// one (Raze + Cipher) and the hacker reads as a Molly-Millions-style
    /// cyber-blade specialist instead of a generic shooter. His pistol is
    /// exposed through SHT; ATK stays monoblade-only and requires adjacency.
    static func decker() -> Character {
        var attrs = AttributeSet.zero
        attrs.bod = 3
        attrs.agi = 3
        attrs.rea = 4
        attrs.str = 2
        attrs.cha = 4
        attrs.int = 5
        attrs.log = 6
        attrs.wil = 3

        var skills = SkillSet.zero
        // Blades 4 — primary now, matches Raze's level so the monoblade
        // lands consistently against guard-tier defense pools.
        skills.blades = 4
        // Firearms 3 — secondary, drops the smartgun pistol to a useful
        // ~6-die backup pool for when targets are out of melee range.
        // Was 4 when this was his primary weapon.
        skills.firearms = 3
        skills.perception = 5
        skills.sneaking = 4
        skills.conjuring = 0
        skills.spellcasting = 0

        // Monoblade — high-tech molecular edge. Same blade class as Raze's
        // katana so the existing melee VFX (slash arc, wet-thunk impact SFX)
        // and the sidearm-fallback branch all apply unmodified. Slightly
        // less damage / AP than Raze's katana — Cipher's a hacker, not a
        // trained swordsman.
        let weapon = Weapon(name: "Monoblade", type: .blade, damage: 6, accuracy: 5, armorPiercing: 2)
        let armor = Armor(name: "Light Armor", armorValue: 2, spellPenalty: 0)

        let character = Character(
            name: "Cipher",
            archetype: .decker,
            attributes: attrs,
            skills: skills,
            weapon: weapon,
            armor: armor,
            maxHP: 14,
            maxMana: 8   // Matrix energy pool for hacking
        )
        return character
    }

    /// Face: high CHA/AGI, social + ranged backup
    static func face() -> Character {
        var attrs = AttributeSet.zero
        attrs.bod = 3
        attrs.agi = 5
        attrs.rea = 4
        attrs.str = 3
        attrs.cha = 6
        attrs.int = 4
        attrs.log = 2
        attrs.wil = 3

        var skills = SkillSet.zero
        skills.firearms = 5
        skills.sneaking = 4
        skills.perception = 3
        skills.blades = 2
        skills.unarmed = 2

        let weapon = Weapon(name: "SMG", type: .smg, damage: 6, accuracy: 5, armorPiercing: 1)
        let armor = Armor(name: "Light Armor", armorValue: 2, spellPenalty: 0)

        let character = Character(
            name: "Lyra",
            archetype: .face,
            attributes: attrs,
            skills: skills,
            weapon: weapon,
            armor: armor,
            maxHP: 14,
            maxMana: 0
        )
        return character
    }

    /// All pre-built runner team
    static var allRunners: [Character] {
        [streetSam(), mage(), decker(), face()]
    }
}
