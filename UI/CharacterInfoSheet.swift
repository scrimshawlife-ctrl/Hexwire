import SwiftUI

// MARK: - Info Sheet
//
// Long-press a runner or enemy on the board to surface this sheet:
//   • Portrait / archetype glyph
//   • Stats (HP/Stun/Mana, attributes, equipped weapon/armor)
//   • Lore blurb (from HEXWIRE-LORE.md for runners; archetype briefs for enemies)
//
// Triggered from BattleScene.handleLongPress, which posts
// `.entityInfoRequested` with one of two payloads:
//   userInfo: ["kind": "player", "characterId": <UUID string>]
//   userInfo: ["kind": "enemy",  "enemyId":     <UUID string>]
// CombatView observes that notification and presents this sheet.

struct CharacterInfoSheet: View {
    let payload: InfoPayload
    let onDismiss: () -> Void

    enum InfoPayload {
        case player(Character)
        case enemy(Enemy)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.78)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            VStack(spacing: 0) {
                header
                Divider()
                    .frame(height: 1)
                    .background(Color(hex: "00FF88").opacity(0.35))
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        statsBlock
                        loadoutBlock
                        cyberwareBlock
                        loreBlock
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                }

                closeButton
            }
            .frame(maxWidth: 360)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(hex: "0A0E18"))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color(hex: "00FF88").opacity(0.55), lineWidth: 1.5)
                    )
            )
            .shadow(color: Color(hex: "00FF88").opacity(0.3), radius: 18)
            .padding(.horizontal, 24)
            .padding(.vertical, 60)
        }
    }

    // MARK: Sections

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            // Sprite portrait — uses the actual idle_0 PNG for the archetype.
            // Falls back to a colored disc + initial if the image can't load
            // (e.g. fresh archetype with no art shipped yet).
            portraitView
                .frame(width: 76, height: 96)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(portraitColor.opacity(0.15))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(portraitColor.opacity(0.6), lineWidth: 1.2)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(displayName.uppercased())
                    .font(.system(size: 20, weight: .black, design: .monospaced))
                    .foregroundColor(.white)
                    .tracking(1)
                HStack(spacing: 8) {
                    Text(archetypeLabel.uppercased())
                        .font(.system(size: 11, weight: .heavy, design: .monospaced))
                        .foregroundColor(Color(hex: "00FF88").opacity(0.85))
                        .tracking(2)
                    Text(levelLabel)
                        .font(.system(size: 11, weight: .black, design: .monospaced))
                        .foregroundColor(.black)
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Capsule().fill(Color(hex: "FFCC00")))
                }
            }
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    /// Loads `<key>_idle_0.png` from Sprites/frames/ and renders it. The
    /// loader hits the same paths SpriteManager uses so it works whether the
    /// asset is bundled or resolved via a folder reference.
    @ViewBuilder
    private var portraitView: some View {
        if let img = portraitImage() {
            Image(uiImage: img)
                .interpolation(.none)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .padding(4)
        } else {
            // Fallback: colored disc + initial (matches the briefing
            // team-roster style).
            ZStack {
                Circle()
                    .fill(portraitColor)
                Text(initial)
                    .font(.system(size: 24, weight: .black, design: .monospaced))
                    .foregroundColor(.black)
            }
            .padding(8)
        }
    }

    private func portraitImage() -> UIImage? {
        // Cached load + background strip via BasementBrawlSpriteCache (same
        // Sprites/frames/ path, same removeBackground cut). SwiftUI re-evaluates
        // this on every body pass — the uncached version re-read the PNG from
        // disk and re-ran a ~600K-pixel flood fill each time, a visible hitch
        // whenever the sheet re-rendered.
        if let img = BasementBrawlSpriteCache.shared.image(named: "\(portraitFrameKey)_idle_0") {
            return img
        }
        // Fallback for paths the cache doesn't probe (resourcePath / source tree).
        guard let raw = rawPortraitImage() else { return nil }
        return BasementBrawlSpriteCache.removeBackground(raw) ?? raw
    }

    private func rawPortraitImage() -> UIImage? {
        let key = portraitFrameKey
        let filename = "\(key)_idle_0.png"
        // 1) Bundle resource URL → Sprites/frames/<file>
        if let resourceURL = Bundle.main.resourceURL {
            let url = resourceURL.appendingPathComponent("Sprites/frames").appendingPathComponent(filename)
            if let img = UIImage(contentsOfFile: url.path) { return img }
        }
        // 2) Bundle resourcePath fallback
        if let resourcePath = Bundle.main.resourcePath {
            let path = resourcePath + "/Sprites/frames/" + filename
            if let img = UIImage(contentsOfFile: path) { return img }
        }
        // 3) Source-relative fallback (only useful when running tests from
        //    the source tree, not in shipped builds — harmless if it misses).
        let sourceURL = URL(fileURLWithPath: #file)
        let url = sourceURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sprites/frames")
            .appendingPathComponent(filename)
        return UIImage(contentsOfFile: url.path)
    }

    /// PNG filename prefix for the portrait. Player archetypes map to their
    /// own sprite key; enemy archetypes share keys with SpriteManager (e.g.
    /// "mage" enemy → "corpmage" frames).
    private var portraitFrameKey: String {
        switch payload {
        case .player(let c):
            switch c.archetype {
            case .streetSam: return "samurai"
            case .mage:      return "mage"
            case .decker:    return "decker"
            case .face:      return "face"
            }
        case .enemy(let e):
            switch e.archetype.lowercased() {
            case "guard":   return "guard"
            case "elite":   return "elite"
            case "drone":   return "drone"
            case "mage", "corpmage": return "corpmage"
            case "bossmage": return "bossmage"   // M3 Sato Unbound — dedicated boss frames
            case "healer", "medic":  return "medic"
            case "boss":    return "boss"
            case "mech":    return "mech"
            case "bossmech": return "bossmech"   // M5 MEKTON-7 — dedicated frames
            case "bossagi":  return "bossagi"    // M6 AGI-PRIME — dedicated frames
            case "sniper":  return "sniper"
            case "bruiser": return "bruiser"
            case "spider":  return "spider"
            case "riot":    return "riot"
            case "turret":  return "turret"
            case "rigger":      return "rigger"
            case "netrunner":   return "netrunner"
            case "grenadier":   return "grenadier"
            case "juggernaut":  return "juggernaut"
            case "infiltrator": return "infiltrator"
            case "repairdrone": return "repairdrone"
            case "sprayer":     return "sprayer"
            default:        return "guard"
            }
        }
    }

    private var statsBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("VITALS")
            HStack(spacing: 14) {
                vital("HP", value: hpText, color: hpColor)
                vital("STUN", value: stunText, color: Color(hex: "FFAA00"))
                if maxMana > 0 {
                    vital("MANA", value: manaText, color: Color(hex: "6699FF"))
                }
            }
            sectionLabel("ATTRIBUTES").padding(.top, 6)
            attrGrid
        }
    }

    private var loadoutBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("LOADOUT")
            if let weapon {
                infoRow("WEAPON",
                        "\(weapon.name) — DMG \(weapon.damage), ACC \(weapon.accuracy), AP \(weapon.armorPiercing)")
            } else {
                infoRow("WEAPON", "None")
            }
            if let armor {
                infoRow("ARMOR",
                        "\(armor.name) — value \(armor.armorValue)\(armor.spellPenalty != 0 ? " · spell \(armor.spellPenalty)" : "")")
            } else {
                infoRow("ARMOR", "None")
            }
        }
    }

    /// Player-only: installed cyberware + the aggregate stat buffs they grant,
    /// so you can see at a glance what kit/enhancements a runner is carrying.
    @ViewBuilder
    private var cyberwareBlock: some View {
        if case .player(let c) = payload {
            VStack(alignment: .leading, spacing: 6) {
                sectionLabel("CYBERWARE & BUFFS")
                if c.installedCyberware.isEmpty {
                    infoRow("IMPLANTS", "None — install at the Black Market")
                } else {
                    ForEach(c.installedCyberware) { cw in
                        infoRow(cw.name.uppercased(), cyberBonusString(cw))
                    }
                    let total = aggregateBuffs(c)
                    if !total.isEmpty { infoRow("TOTAL", total) }
                }
            }
        }
    }

    private func cyberBonusString(_ cw: Cyberware) -> String {
        var parts: [String] = []
        if cw.soak != 0         { parts.append("+\(cw.soak) soak") }
        if cw.initiative != 0   { parts.append("+\(cw.initiative) init") }
        if cw.accuracyDice != 0 { parts.append("+\(cw.accuracyDice) acc") }
        if cw.defenseDice != 0  { parts.append("+\(cw.defenseDice) def") }
        if cw.maxHP != 0        { parts.append("+\(cw.maxHP) HP") }
        return parts.isEmpty ? cw.blurb : parts.joined(separator: ", ")
    }

    private func aggregateBuffs(_ c: Character) -> String {
        var parts: [String] = []
        if c.cyberSoak != 0         { parts.append("+\(c.cyberSoak) soak") }
        if c.cyberInitiative != 0   { parts.append("+\(c.cyberInitiative) init") }
        if c.cyberAccuracyDice != 0 { parts.append("+\(c.cyberAccuracyDice) acc dice") }
        if c.cyberDefenseDice != 0  { parts.append("+\(c.cyberDefenseDice) def dice") }
        return parts.joined(separator: " · ")
    }

    private var loreBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("DOSSIER")
            Text(loreText)
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(Color.white.opacity(0.85))
                .lineSpacing(3)
        }
    }

    private var closeButton: some View {
        Button(action: onDismiss) {
            Text("CLOSE")
                .font(.system(size: 13, weight: .heavy, design: .monospaced))
                .foregroundColor(.black)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(Color(hex: "00FF88"))
        }
    }

    // MARK: Subviews

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .black, design: .monospaced))
            .foregroundColor(Color(hex: "00FF88").opacity(0.7))
            .tracking(2)
    }

    private func vital(_ label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 8, weight: .heavy, design: .monospaced))
                .foregroundColor(color.opacity(0.8))
                .tracking(1)
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundColor(color)
        }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.system(size: 9, weight: .heavy, design: .monospaced))
                .foregroundColor(Color(hex: "00FF88").opacity(0.7))
                .tracking(1)
                .frame(width: 56, alignment: .leading)
            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.white)
        }
    }

    private var attrGrid: some View {
        let pairs: [(String, Int)] = attrs
        let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
        return LazyVGrid(columns: columns, spacing: 6) {
            ForEach(pairs, id: \.0) { pair in
                VStack(spacing: 1) {
                    Text(pair.0)
                        .font(.system(size: 8, weight: .heavy, design: .monospaced))
                        .foregroundColor(Color.white.opacity(0.55))
                    Text("\(pair.1)")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .background(Color(hex: "0F1320"))
                .cornerRadius(4)
            }
        }
    }

    // MARK: Data extraction

    private var displayName: String {
        switch payload {
        case .player(let c): return c.name
        case .enemy(let e):  return e.name
        }
    }

    private var levelLabel: String {
        switch payload {
        case .player(let c): return "LVL \(c.level)"
        // Enemies have no XP level; their level is a danger readout — a base
        // ramp across the campaign (+1 for bosses) plus the NG+ tier. Shared
        // with the in-combat HP-bar badge so the two always agree.
        case .enemy(let e):
            return "LVL \(MissionStatsStore.enemyDisplayLevel(missionId: GameState.shared.currentMissionDisplayId, archetype: e.archetype))"
        }
    }

    private var archetypeLabel: String {
        switch payload {
        case .player(let c):
            switch c.archetype {
            case .streetSam: return "Street Samurai"
            case .mage:      return "Combat Mage"
            case .decker:    return "Netrunner"
            case .face:      return "Face"
            }
        case .enemy(let e):
            return EnemyLore.label(for: e.archetype)
        }
    }

    private var initial: String {
        String(displayName.prefix(1)).uppercased()
    }

    private var portraitColor: Color {
        switch payload {
        case .player(let c):
            switch c.archetype {
            case .streetSam: return Color(hex: "00FF88")
            case .mage:      return Color(hex: "6699FF")
            case .decker:    return Color(hex: "FF8800")
            case .face:      return Color(hex: "FF44AA")
            }
        case .enemy(let e):
            return Color(hex: EnemyLore.colorHex(for: e.archetype))
        }
    }

    private var hpText: String {
        switch payload {
        case .player(let c): return "\(c.currentHP)/\(c.maxHP)"
        case .enemy(let e):  return "\(e.currentHP)/\(e.maxHP)"
        }
    }

    private var hpColor: Color {
        let pct: Double = {
            switch payload {
            case .player(let c): return Double(c.currentHP) / Double(max(1, c.maxHP))
            case .enemy(let e):  return Double(e.currentHP) / Double(max(1, e.maxHP))
            }
        }()
        return pct > 0.5 ? Color(hex: "00FF88")
             : pct > 0.25 ? Color(hex: "FFAA00")
                          : Color(hex: "FF3344")
    }

    private var stunText: String {
        switch payload {
        case .player(let c): return "\(c.currentStun)/\(c.maxStun)"
        case .enemy(let e):  return "\(e.currentStun)/\(e.maxStun)"
        }
    }

    private var maxMana: Int {
        switch payload {
        case .player(let c): return c.maxMana
        case .enemy: return 0
        }
    }

    private var manaText: String {
        switch payload {
        case .player(let c): return "\(c.currentMana)/\(c.maxMana)"
        case .enemy: return "—"
        }
    }

    private var attrs: [(String, Int)] {
        let a: AttributeSet = {
            switch payload {
            case .player(let c): return c.attributes
            case .enemy(let e):  return e.attributes
            }
        }()
        return [
            ("BOD", a.bod), ("AGI", a.agi), ("REA", a.rea), ("STR", a.str),
            ("CHA", a.cha), ("INT", a.int), ("LOG", a.log), ("WIL", a.wil)
        ]
    }

    private var weapon: Weapon? {
        switch payload {
        case .player(let c): return c.equippedWeapon
        case .enemy(let e):  return e.equippedWeapon
        }
    }

    private var armor: Armor? {
        switch payload {
        case .player(let c): return c.equippedArmor
        case .enemy(let e):  return e.equippedArmor
        }
    }

    private var loreText: String {
        switch payload {
        case .player(let c): return RunnerLore.dossier(for: c)
        case .enemy(let e):  return EnemyLore.dossier(for: e.archetype)
        }
    }
}

// MARK: - Runner Lore (sourced from HEXWIRE-LORE.md)

enum RunnerLore {
    static func dossier(for char: Character) -> String {
        let name = char.name.lowercased()
        if name.contains("raze")  { return raze }
        if name.contains("sable") { return sable }
        if name.contains("cipher") { return cipher }
        if name.contains("lyra")  { return lyra }
        // Fallback by archetype
        switch char.archetype {
        case .streetSam: return raze
        case .mage:      return sable
        case .decker:    return cipher
        case .face:      return lyra
        }
    }

    static let raze = """
    "I don't run. I end things."

    Former military — corpo black ops, discharged after a mission in the Chicago Containment Zone went sideways. The chrome he wears now replaced what that mission took from him, piece by piece.

    Violence is math to him. He doesn't enjoy it — he just doesn't flinch either.
    """

    static let sable = """
    "The world's louder than you think. I hear what's underneath."

    Witch-born in the Redmond barrens, harder than the spirits that tried to claim her. Sable talks to the things that live in the gaps — data streams, dead orbits, echoes in old code.

    She goes quiet before something bad happens. The team has learned to listen.
    """

    static let cipher = """
    "I don't break in. I already live in the cracks."

    Ex-corporate analyst at Atlas Pacific. They noticed he'd been accessing files he shouldn't. By Wednesday he was three aliases deep and running.

    The wire is the only place he feels real. Meat space is messy. Slow. Full of people with guns and bad intentions.
    """

    static let lyra = """
    "Say the right thing to the wrong person and they hand you the keys."

    Combat-zone kid who learned to talk fast or die young. Not a hacker, not a mage, not a killer — just someone who walks into a room and leaves it different.

    Asks too many questions in rooms she should be quiet in. Can't help it. It's how she knows what's real.
    """
}

// MARK: - Enemy Lore (per archetype)

enum EnemyLore {
    static func label(for archetype: String) -> String {
        switch archetype.lowercased() {
        case "guard":   return "Corp Security"
        case "elite":   return "Knight Errant Elite"
        case "drone":   return "Security Drone"
        case "mage", "corpmage": return "Corp Combat Mage"
        case "bossmage":         return "Blood Mage — Sato"
        case "healer", "medic":  return "Field Medic"
        case "boss", "mech":     return "Combat Mech"
        case "bossmech":         return "MEKTON-7"
        case "bossagi":          return "AGI-PRIME"
        case "sniper":  return "Sniper / Marksman"
        case "bruiser": return "Shock Trooper"
        case "spider":  return "Spider Drone"
        case "riot":    return "Riot Trooper"
        case "turret":  return "Sentry Turret"
        case "rigger":      return "Rigger / Drone Master"
        case "netrunner":   return "Combat Decker"
        case "grenadier":   return "Grenadier"
        case "juggernaut":  return "Cyber-Zombie"
        case "infiltrator": return "Infiltrator"
        case "repairdrone": return "Repair Drone"
        case "sprayer":     return "Toxic Sprayer"
        default:        return archetype.capitalized
        }
    }

    static func colorHex(for archetype: String) -> String {
        switch archetype.lowercased() {
        case "guard":   return "FF4444"
        case "elite":   return "CC00FF"
        case "drone":   return "FF8800"
        case "mage", "corpmage": return "00CCFF"
        case "bossmage":         return "FF1133"   // blood-red — M3 boss
        case "healer", "medic":  return "FF44AA"
        case "boss", "mech":     return "FFCC00"
        case "bossmech":         return "FF7700"   // hazard orange — M5 boss
        case "bossagi":          return "00E5FF"   // electric cyan — M6 boss
        case "sniper":  return "22FF66"
        case "bruiser": return "FF3333"
        case "spider":  return "00FFCC"
        case "riot":    return "3366FF"
        case "turret":  return "FF2222"
        case "rigger":      return "22CCAA"
        case "netrunner":   return "00E5FF"
        case "grenadier":   return "FFAA22"
        case "juggernaut":  return "CC3322"
        case "infiltrator": return "8844FF"
        case "repairdrone": return "FFCC33"
        case "sprayer":     return "88DD22"
        default:        return "FF3333"
        }
    }

    static func dossier(for archetype: String) -> String {
        switch archetype.lowercased() {
        case "guard":
            return "Standard-issue corp security. Knight Errant cast-offs and budget mall cops, smartlinked pistols and a Class-II vest. Not the best you'll fight today. Not the worst either."
        case "elite":
            return "Knight Errant Special Tactics. The corps wheel them out when the brief reads 'do not let runners reach the executive floor.' Assault rifles, medium armor, and they actually learned to use cover."
        case "drone":
            return "Renraku Optic-X security drone. Suspended on rotors, packs a smartgun, software-driven pattern recognition. Fragile glass — once it's down, it stays down."
        case "mage", "corpmage":
            return "In-house corporate Awakened. Picks off targets with stunballs and manabolts from the back line. Not as scary as a street shaman, but the corp pays them more, so they never run out of mana focuses."
        case "bossmage":
            return "Sato. Blood mage holed up in the Barrens, pulling tithes from the homeless camps for six months. His grimoire fuels every spell. Kill him fast — every round he lives, more wards lock down. The book on the altar is yours when he stops breathing."
        case "healer", "medic":
            return "Combat medic with a stim-pack and a stunbaton. Spends his rounds patching the squad behind him. Drop him FIRST — every elite he revives is another problem you have to solve twice."
        case "boss", "mech":
            return "Corporate combat mech. Autocannon, mech plating, and just enough AI to recognize threats. Slow. Heavy. Hits like a truck. Bring AP rounds or don't bother."
        case "bossmech":
            return "MEKTON-7 — Drachenwerk's prototype. Twelve feet tall, reactive armor, heavy autocannon. They're slow on the right side. ALWAYS slow on the right. Burn through the armor, watch the corner, and don't stand still."
        case "bossagi":
            return "AGI-PRIME — Mitsuhama's runaway artificial general intelligence projecting a combat avatar through hijacked drone hardware. Phase-shifts between attacks (move 3 tiles per turn), Reality Glitch beam at range 6, soft armor but hard to pin. Spell-resistant. Cipher's the only one with a clean line into it."
        case "sniper":
            return "Ghillie-suited marksman, holed up at long range. Hits hard but folds the moment you close to bayonet range. Sable's manabolt does NOT care about ghillie suits."
        case "bruiser":
            return "Cybered-up shock trooper. Six feet of muscle and chrome with a stun baton wired into his nervous system. Loves to charge. Hates being shot at range."
        case "spider":
            return "Quadruped scout drone — the corp's answer to 'we need to clear corridors fast.' Fragile but mobile, taser-armed, used to harass deckers off their gear."
        case "riot":
            return "Riot Trooper. Carries a ballistic shield and a riot shotgun. Slow but armored to the teeth. Designed for crowd control — turns out 'the crowd' includes wirerunners."
        case "turret":
            return "Bolted-down sentry autocannon. Can't move, but it doesn't need to — high accuracy, heavy AP, and a clear field of fire. Break line-of-sight or rush it."
        case "rigger":
            return "Street rigger jacked into a drone rig. Doesn't fight you directly — it SUMMONS combat drones every turn from its deck. Kill the rigger and the drones stop coming. Let it work and you'll drown in rotors."
        case "netrunner":
            return "Enemy decker. Fires DATA SPIKES — matrix attacks that bypass armor and cyberware entirely (they soak on Willpower alone) and stack STUN. Max a runner's stun and they're frozen out of the round. Squishy meat, lethal brain. Silence it fast."
        case "grenadier":
            return "Heavy weapons trooper with a grenade launcher. Lobs AoE that catches everyone adjacent to the blast — so DON'T cluster. Tanky and armored, but slow. Spread out and burn it down."
        case "juggernaut":
            return "Cyber-zombie juggernaut — a man turned into a walking wall of bolted chrome. Forty-plus HP, heavy plating, hydraulic fists that cave in armor. Moves one tile a turn. Kite it, focus it, and whatever you do, don't get cornered."
        case "infiltrator":
            return "Optical-camo assassin. Lightning reflexes make it brutal to hit, and it moves three tiles to flank your backline and drive a monofilament blade through your armor. Glass once you pin it — but pinning it is the trick."
        case "repairdrone":
            return "Autonomous repair unit. Welds your MECHANICAL problems back together — drones, mechs, turrets — every single turn. Harmless on its own. Leave it alive and the machines never stay dead. Prioritize it."
        case "sprayer":
            return "Hazmat sapper with a chem-sprayer. Lays down a corrosive cone that pierces armor AND leaves a lingering CORROSION that keeps eating at you after you've moved. Area denial — keep moving, don't bunch up."
        default:
            return "No additional intel."
        }
    }
}
