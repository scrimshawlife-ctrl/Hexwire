import SwiftUI

// MARK: - Info Sheet
//
// Long-press a runner or enemy on the board to surface this sheet:
//   • Portrait / archetype glyph
//   • Stats (HP/Stun/Mana, attributes, equipped weapon/armor)
//   • Lore blurb (from SHADOWRUN-LORE.md for runners; archetype briefs for enemies)
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
                Text(archetypeLabel.uppercased())
                    .font(.system(size: 11, weight: .heavy, design: .monospaced))
                    .foregroundColor(Color(hex: "00FF88").opacity(0.85))
                    .tracking(2)
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

// MARK: - Runner Lore (sourced from SHADOWRUN-LORE.md)

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
            return "Lockheed Optic-X security drone. Suspended on rotors, packs a smartgun, software-driven pattern recognition. Fragile glass — once it's down, it stays down."
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
        default:
            return "No additional intel."
        }
    }
}
