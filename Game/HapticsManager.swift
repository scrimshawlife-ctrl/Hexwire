import UIKit

/// Centralized haptics for combat and UI feedback
@MainActor
final class HapticsManager {
    static let shared = HapticsManager()

    /// Master haptics switch (Settings). When false every call is a no-op.
    var enabled: Bool = true
    
    private let light = UIImpactFeedbackGenerator(style: .light)
    private let medium = UIImpactFeedbackGenerator(style: .medium)
    private let heavy = UIImpactFeedbackGenerator(style: .heavy)
    private let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private let soft = UIImpactFeedbackGenerator(style: .soft)
    private let notification = UINotificationFeedbackGenerator()
    
    private init() {
        // Pre-warm generators
        light.prepare()
        medium.prepare()
        heavy.prepare()
        rigid.prepare()
        soft.prepare()
        notification.prepare()
    }
    
    // MARK: - Combat
    
    func attackHit() {
        guard enabled else { return }
        heavy.impactOccurred()
    }
    
    func attackMiss() {
        guard enabled else { return }
        light.impactOccurred()
    }

    /// Silent combat input (attack-button press / swing). Haptic only — no UI
    /// beep, so rapid attacks in the brawl don't chirp on every tap.
    func combatInput() {
        guard enabled else { return }
        medium.impactOccurred()
    }
    
    func playerDamaged() {
        guard enabled else { return }
        notification.notificationOccurred(.warning)
    }
    
    func enemyKilled() {
        guard enabled else { return }
        notification.notificationOccurred(.success)
    }
    
    func playerKilled() {
        guard enabled else { return }
        notification.notificationOccurred(.error)
    }
    
    func levelUp() {
        guard enabled else { return }
        notification.notificationOccurred(.success)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            self.rigid.impactOccurred()
        }
    }
    
    // MARK: - UI Navigation
    
    func buttonTap() {
        guard enabled else { return }
        light.impactOccurred()
        SFXManager.shared.play("ui_tap", volume: 0.6)
    }

    func selectionChanged() {
        guard enabled else { return }
        medium.impactOccurred()
        SFXManager.shared.play("ui_tap", volume: 0.54)   // −10% from 0.6
    }

    /// Affirmative commit-style button (NEW RUN, ACCEPT CONTRACT, mission row).
    func selectAffirm() {
        guard enabled else { return }
        medium.impactOccurred()
        SFXManager.shared.play("ui_select", volume: 0.63)  // −10% from 0.7
    }

    /// Back / cancel / abort / dismiss.
    func back() {
        guard enabled else { return }
        light.impactOccurred()
        SFXManager.shared.play("ui_back", volume: 0.6)
    }

    /// Invalid action — out of range, not enough mana, already moved, etc.
    func error() {
        guard enabled else { return }
        rigid.impactOccurred()
        SFXManager.shared.play("ui_error", volume: 0.7)
    }

    /// Lock release — door open, terminal unlock, mini-game success.
    func unlock() {
        guard enabled else { return }
        soft.impactOccurred()
        SFXManager.shared.play("ui_unlock", volume: 0.75)
    }
    
    func menuOpen() {
        guard enabled else { return }
        soft.impactOccurred()
    }
    
    // MARK: - Movement / Tile
    
    func tileTap() {
        guard enabled else { return }
        light.impactOccurred()
    }
    
    func moveConfirm() {
        guard enabled else { return }
        medium.impactOccurred()
    }
    
    // MARK: - Phase Transitions
    
    func roundStart() {
        guard enabled else { return }
        notification.notificationOccurred(.warning)
    }
    
    func combatStart() {
        guard enabled else { return }
        heavy.impactOccurred()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.medium.impactOccurred()
        }
    }
    
    func victory() {
        guard enabled else { return }
        notification.notificationOccurred(.success)
    }
    
    func defeat() {
        guard enabled else { return }
        notification.notificationOccurred(.error)
    }
}
