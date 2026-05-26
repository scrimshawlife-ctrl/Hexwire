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
    case doors
    case terminals

    var title: String {
        switch self {
        case .combatBasics: return "RUN BASICS"
        case .utilityRow:   return "TOP ROW HUD"
        case .doors:        return "LEAVING A ROOM"
        case .terminals:    return "DATA TERMINAL"
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
              SHT — ranged shot
              DEF — brace, take less damage next hit
              BLITZ/SPELL/HACK/SCHMZ — runner ability
              ITM — use stim or grenade
              END — pass the rest of the turn

            A runner gets ONE move and ONE action per turn.
            """
        case .utilityRow:
            return """
            Top row of buttons:

            • MODE — STREET fights enemies; SIGNAL routes Matrix/Astral plays. Stay on STREET for combat.
            • LAY LOW — once per mission, recover trace heat. Burns the runner's turn.
            • INTEL — open the mission objective + threat sheet. Free to toggle.
            • DIAG — debug overlay (dice rolls, AI intent). Off by default.
            """
        case .doors:
            return """
            Yellow flashing tiles are doors. To leave a room:

            1. Clear (or sneak past) the room's enemies
            2. Walk a runner adjacent to the door
            3. Tap the door — your runner steps in
            4. Tap again to actually cross; the team follows

            Multi-room missions use this between zones; single-room runs use the EXTRACTION arrow instead.
            """
        case .terminals:
            return """
            Cyan tiles are data terminals — the mission objective requires hacking one before extraction.

            1. Watch for the cyan tile (the INTEL panel pings its location)
            2. Walk a runner (ideally Cipher) adjacent
            3. Tap the terminal to start the intrusion
            4. The tile darkens once cracked — head to extraction

            If Cipher goes down, any runner can hack — at a steep dice penalty.
            """
        }
    }

    fileprivate var udKey: String { "TutorialSeen_\(rawValue)" }
}

@MainActor
final class TutorialCoach: ObservableObject {
    static let shared = TutorialCoach()

    @Published var current: TutorialTip? = nil
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
        if let tip = coach.current {
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
