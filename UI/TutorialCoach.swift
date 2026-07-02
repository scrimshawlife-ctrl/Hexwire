import SwiftUI

// MARK: - Tutorial Coach
//
// First-time-only tooltip cards shown over the combat HUD. Each tip is
// shown ONCE per install — once dismissed (or auto-acked by the relevant
// gameplay event), the UserDefaults flag flips and we never bother the
// player again. Designed to be cheap to add new cards: append a case to
// `TutorialTip`, give it a title/body/copy, and enqueue it from the
// appropriate game-state observer.
//
// The coach is a shared singleton with a small queue. Only one card is on
// screen at a time; if multiple trigger together, they show in order so
// nothing is missed.

enum TutorialTip: String, CaseIterable {
    case combatBasics
    case utilityRow
    case signalHeat
    case doors
    case terminals
    case blackMarket
    case newGamePlus
    case missionRanks
    case hackResisted

    var title: String {
        switch self {
        case .combatBasics: return "RUN BASICS"
        case .utilityRow:   return "TOP ROW HUD"
        case .signalHeat:   return "SIGNAL & TRACE"
        case .doors:        return "LEAVING A ROOM"
        case .terminals:    return "DATA TERMINAL"
        case .blackMarket:  return "BLACK MARKET"
        case .newGamePlus:  return "NEW GAME+"
        case .missionRanks: return "MISSION RANK"
        case .hackResisted: return "HARDENED ICE"
        }
    }

    /// Multi-line body — kept short so it doesn't dominate the screen. Use
    /// "•" for bullets; literal newlines render as line breaks.
    var body: String {
        switch self {
        case .combatBasics:
            return """
            On your turn:

            • Tap a teammate to switch runners
            • Tap an empty hex to move there — you can move up to 2 tiles
            • Tap an enemy to target it, then hit:
              ATK — melee strike (adjacent only)
              SHT — ranged shot (hold for OVERWATCH)
              DEF — brace, take less damage next hit
              BLITZ/SPELL/HACK/INTIM — runner ability (samurai/mage/decker/face)
              ITM — use stim or grenade
              END — pass the rest of the turn

            Hold SHT for OVERWATCH: the runner holds fire and auto-shoots the first enemy that steps into their line of sight on the enemy's turn.

            A runner gets ONE move OR ONE action per turn — moving uses your whole turn.

            GOOD TO KNOW:
            • Long-press any runner OR enemy to see their full stats, gear, cyberware, and level.
            • Ranged shots LOSE accuracy past their range (you'll see "range −Xd") — close in for reliable hits.
            • HACK & INTIM can be RESISTED — tough/boss enemies shrug them off; grunts fold.
            • Spend nuyen between runs at the BLACK MARKET (gear, cyberware, spells). Beat the campaign to unlock NEW GAME+ (your runners carry over, the opposition escalates).
            """
        case .utilityRow:
            return """
            Top row of buttons:

            • MODE — toggle STREET ⟷ SIGNAL. STREET is the safe default; SIGNAL
               is the aggressive "run hot" stance (it gets its own card when you
               first switch to it).
            • LAY LOW — brace (+2 DEF) AND vent TRACE heat. Uses the runner's turn.
            • INTEL — open the mission objective + threat sheet. Free to toggle.
            """
        case .signalHeat:
            return """
            STREET vs SIGNAL is the core risk/reward dial:

            • STREET — quiet. No bonus, but TRACE never builds. Safe and slow.
            • SIGNAL — jacked in. Every action adds TRACE heat, but you hit
               HARDER and CRIT more — and it SCALES with the heat:
                  LOW  → SIGNAL +1 die
                  MED  → +2 dice, spells −1 mana
                  HIGH → +3 dice, crits land easier, spells −1 mana
            • You MUST be in SIGNAL to hack terminals or run matrix intrusions —
               jacking in spikes TRACE hard.

            TRACE cuts both ways: the hotter it runs, the harder THEY hit too,
            and at HIGH the host scrambles a security reinforcement onto the
            board. Tap LAY LOW to brace (+2 DEF) and vent the heat — it's a
            defensive reset, never a wasted turn.

            The loop: go SIGNAL to burst things down, ride the heat for bigger
            dice and crits, then LAY LOW before it cooks you.
            """
        case .doors:
            return """
            Orange pulsing tiles are doors. To leave a room:

            1. Clear the room's enemies
            2. Walk a runner adjacent to the door
            3. Tap the door — your runner steps in
            4. Tap again to actually cross; the team follows
            """
        case .terminals:
            return """
            Look for the cyan tile — a data terminal, usually near the center of a room. The mission objective requires hacking it before extraction.

            1. Watch for the cyan tile (the INTEL panel pings its location)
            2. Walk Cipher adjacent — only Cipher can hack the terminal
            3. Tap the terminal to start the intrusion (a quick mini-game)
            4. The tile darkens once cracked — head to extraction

            Only Cipher can hack the terminal. If Cipher is dead, any runner can hack it instead.
            """
        case .blackMarket:
            return """
            Between runs, spend your nuyen at the BLACK MARKET:

            • WEAPONS / ARMOR — equip a runner; better gear, better odds.
            • CYBERWARE — PERMANENT implants (soak, accuracy, initiative, HP). Each implant can be installed ONCE per runner and can't be removed — choose deliberately.
            • SPELLS — teach the mage new spells (Power Bolt, Storm Bolt).

            Everything you buy carries forward for the rest of the campaign. Nuyen is tight on purpose — you can kit out a couple of runners per run, not the whole team, so prioritize.
            """
        case .newGamePlus:
            return """
            You beat the campaign — NEW GAME+ is unlocked.

            • Your runners KEEP everything: levels, stats, gear, cyberware.
            • The opposition ESCALATES: enemies gain HP, hit harder, field extra bodies, and their displayed LEVEL climbs each NG+ tier.
            • Mission payouts RESET, so you can re-earn the economy and keep upgrading.

            It's the same six missions, tuned hotter — a victory lap that fights back. Push as many tiers as you can.
            """
        case .missionRanks:
            return """
            Every cleared mission earns a RANK — S, A, B, or C.

            Your score rewards:
            • SURVIVAL — keep runners alive
            • KILLS — clean sweeps
            • OBJECTIVE — grab the data / bonus haul
            • SPEED — fewer rounds = higher efficiency bonus

            Only your BEST rank per mission is kept, so replay to push a C up to an S. (Replays don't re-pay nuyen — the payout is once per run-through.)
            """
        case .hackResisted:
            return """
            That intrusion was RESISTED.

            HACK (decker) and INTIM (face) are opposed by the target's WILL — tough enemies and bosses run hardened defenses (+2) and will sometimes shrug them off, while low-will grunts fold easily.

            They're control tools, not guarantees: lean on them against the rank-and-file, and don't count on locking down a boss every turn.
            """
        }
    }

    fileprivate var udKey: String { "TutorialSeen_\(rawValue)" }
}

@MainActor
final class TutorialCoach: ObservableObject {
    static let shared = TutorialCoach()

    @Published var current: TutorialTip? = nil
    /// Drives the on-demand HELP menu (a picker of every card to re-read).
    @Published var showMenu: Bool = false
    private var pending: [TutorialTip] = []
    private var inFlight: Set<TutorialTip> = []

    /// Enqueue a tip. No-op if it's already been seen, is currently shown,
    /// or is already queued.
    func enqueue(_ tip: TutorialTip) {
        guard !UserDefaults.standard.bool(forKey: tip.udKey) else { return }
        guard current != tip, !inFlight.contains(tip) else { return }
        inFlight.insert(tip)
        pending.append(tip)
        if current == nil { advance() }
    }

    /// Dismiss the currently-displayed tip and pop the next from the queue
    /// (if any).
    func dismissCurrent() {
        if let c = current {
            UserDefaults.standard.set(true, forKey: c.udKey)
            inFlight.remove(c)
        }
        current = nil
        // Small delay so the dismiss animation completes before the next
        // card pops, otherwise the transition can stutter.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self] in
            self?.advance()
        }
    }

    /// Force a tip on screen regardless of whether it's already been seen.
    /// Backs the in-combat "?" help button so the player can re-read the
    /// basics on demand.
    func forceShow(_ tip: TutorialTip) {
        inFlight.insert(tip)
        current = tip
    }

    /// Reset all tutorial flags. Useful from a debug menu or for QA runs.
    func resetAll() {
        for t in TutorialTip.allCases {
            UserDefaults.standard.removeObject(forKey: t.udKey)
        }
        pending.removeAll()
        inFlight.removeAll()
        current = nil
    }

    private func advance() {
        guard current == nil else { return }
        while let next = pending.first {
            pending.removeFirst()
            if UserDefaults.standard.bool(forKey: next.udKey) {
                inFlight.remove(next)
                continue
            }
            current = next
            return
        }
    }
}

// MARK: - Card View

struct TutorialCard: View {
    let tip: TutorialTip
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Text("◆  \(tip.title)")
                    .font(.system(size: 11, weight: .black, design: .monospaced))
                    .tracking(3)
                    .foregroundColor(Color(hex: "00FFCC"))
                Spacer()
                Button(action: onDismiss) {
                    Text("GOT IT")
                        .font(.system(size: 10, weight: .black, design: .monospaced))
                        .tracking(2)
                        .foregroundColor(Color(hex: "00FFCC"))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.black.opacity(0.7))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(Color(hex: "00FFCC"), lineWidth: 1.2)
                                )
                        )
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
            }
            Text(tip.body)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(Color.white.opacity(0.92))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(2)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.black.opacity(0.92))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color(hex: "00FFCC").opacity(0.65), lineWidth: 1.2)
                )
                .shadow(color: Color(hex: "00FFCC").opacity(0.35), radius: 10)
        )
        .padding(.horizontal, 16)
    }
}

// MARK: - Container Overlay
//
// Drop this anywhere inside the CombatUI ZStack — it positions itself at
// the top of the screen below the safe area and animates in/out as cards
// pop. Tappable area is the GOT IT button only; the rest of the card is
// non-interactive so taps fall through to combat input behind it.

struct TutorialCoachOverlay: View {
    @ObservedObject var coach: TutorialCoach = .shared

    var body: some View {
        // Important: conditionally render the ENTIRE overlay so when no
        // tip is showing the view tree contains nothing — no Spacer, no
        // padding, no hit-test surface that could swallow combat input.
        // Earlier version used a VStack + Spacer and kept that surface
        // alive even with hit-testing disabled; SwiftUI still routed taps
        // there during/after the transition, leaving the play area
        // unresponsive after the last card dismissed.
        if coach.showMenu {
            TutorialMenu(
                onPick: { tip in coach.showMenu = false; coach.forceShow(tip) },
                onClose: { coach.showMenu = false }
            )
        } else if let tip = coach.current {
            VStack(spacing: 0) {
                TutorialCard(tip: tip, onDismiss: coach.dismissCurrent)
                    .padding(.top, 64)   // Clear the Dynamic Island.
                    .transition(.move(edge: .top).combined(with: .opacity))
                Spacer(minLength: 0)
                    .allowsHitTesting(false)  // Spacer below card is decorative.
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .animation(.easeInOut(duration: 0.22), value: tip)
        }
    }
}

// MARK: - Help Menu
//
// Backs the in-combat "?" button: a scrollable list of every tutorial card so
// the player can re-read any topic on demand (not just combat basics).

struct TutorialMenu: View {
    let onPick: (TutorialTip) -> Void
    let onClose: () -> Void

    var body: some View {
        ZStack(alignment: .top) {
            // Dim scrim — tap anywhere outside the panel to close.
            Color.black.opacity(0.55).ignoresSafeArea()
                .onTapGesture { onClose() }

            VStack(spacing: 0) {
                HStack {
                    Text("◆  HELP")
                        .font(.system(size: 12, weight: .black, design: .monospaced))
                        .tracking(3)
                        .foregroundColor(Color(hex: "00FFCC"))
                    Spacer()
                    Button(action: onClose) {
                        Text("CLOSE")
                            .font(.system(size: 10, weight: .black, design: .monospaced))
                            .tracking(2)
                            .foregroundColor(Color(hex: "00FFCC"))
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(RoundedRectangle(cornerRadius: 4).fill(Color.black.opacity(0.7))
                                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(hex: "00FFCC"), lineWidth: 1.2)))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.bottom, 8)

                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(TutorialTip.allCases, id: \.self) { tip in
                            Button(action: { onPick(tip) }) {
                                HStack {
                                    Text(tip.title)
                                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                                        .foregroundColor(.white.opacity(0.92))
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(Color(hex: "00FFCC").opacity(0.7))
                                }
                                .padding(.horizontal, 12).padding(.vertical, 10)
                                .background(RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.white.opacity(0.06))
                                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(hex: "00FFCC").opacity(0.25), lineWidth: 1)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: 360)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.94))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: "00FFCC").opacity(0.65), lineWidth: 1.2)))
            .padding(.horizontal, 16)
            .padding(.top, 64)
            .frame(maxHeight: 460)
        }
    }
}
