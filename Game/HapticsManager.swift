import UIKit

/// Centralized haptics for combat and UI feedback
@MainActor
final class HapticsManager {
    static let shared = HapticsManager()
    
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
        heavy.impactOccurred()
    }
    
    func attackMiss() {
        light.impactOccurred()
    }

    /// Silent combat input (attack-button press / swing). Haptic only — no UI
    /// beep, so rapid attacks in the brawl don't chirp on every tap.
    func combatInput() {
        medium.impactOccurred()
    }
    
    func playerDamaged() {
        notification.notificationOccurred(.warning)
    }
    
    func enemyKilled() {
        notification.notificationOccurred(.success)
    }
    
    func playerKilled() {
        notification.notificationOccurred(.error)
    }
    
    func levelUp() {
        notification.notificationOccurred(.success)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            self.rigid.impactOccurred()
        }
    }
    
    // MARK: - UI Navigation
    
    func buttonTap() {
        light.impactOccurred()
        SFXManager.shared.play("ui_tap", volume: 0.6)
    }

    func selectionChanged() {
        medium.impactOccurred()
        SFXManager.shared.play("ui_tap", volume: 0.54)   // −10% from 0.6
    }

    /// Affirmative commit-style button (NEW RUN, ACCEPT CONTRACT, mission row).
    func selectAffirm() {
        medium.impactOccurred()
        SFXManager.shared.play("ui_select", volume: 0.63)  // −10% from 0.7
    }

    /// Back / cancel / abort / dismiss.
    func back() {
        light.impactOccurred()
        SFXManager.shared.play("ui_back", volume: 0.6)
    }

    /// Invalid action — out of range, not enough mana, already moved, etc.
    func error() {
        rigid.impactOccurred()
        SFXManager.shared.play("ui_error", volume: 0.7)
    }

    /// Lock release — door open, terminal unlock, mini-game success.
    func unlock() {
        soft.impactOccurred()
        SFXManager.shared.play("ui_unlock", volume: 0.75)
    }
    
    func menuOpen() {
        soft.impactOccurred()
    }
    
    // MARK: - Movement / Tile
    
    func tileTap() {
        light.impactOccurred()
    }
    
    func moveConfirm() {
        medium.impactOccurred()
    }
    
    // MARK: - Phase Transitions
    
    func roundStart() {
        notification.notificationOccurred(.warning)
    }
    
    func combatStart() {
        heavy.impactOccurred()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.medium.impactOccurred()
        }
    }
    
    func victory() {
        notification.notificationOccurred(.success)
    }
    
    func defeat() {
        notification.notificationOccurred(.error)
    }
}
