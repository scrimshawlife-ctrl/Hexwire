import SwiftUI

// MARK: - Player Settings (persisted)

/// Tiny UserDefaults-backed settings store. Applied to the live audio /
/// haptics singletons at app launch (HexwireApp) and live from the sheet.
enum PlayerSettings {
    private static let musicKey   = "HexWire.Settings.MusicVolume.v1"
    private static let sfxKey     = "HexWire.Settings.SFXVolume.v1"
    private static let hapticsKey = "HexWire.Settings.Haptics.v1"

    /// Defaults mirror the tuned shipping mix (music 0.55 / SFX 0.85).
    static var musicVolume: Float {
        get { (UserDefaults.standard.object(forKey: musicKey) as? NSNumber)?.floatValue ?? 0.55 }
        set { UserDefaults.standard.set(newValue, forKey: musicKey) }
    }
    static var sfxVolume: Float {
        get { (UserDefaults.standard.object(forKey: sfxKey) as? NSNumber)?.floatValue ?? 0.85 }
        set { UserDefaults.standard.set(newValue, forKey: sfxKey) }
    }
    static var hapticsEnabled: Bool {
        get { (UserDefaults.standard.object(forKey: hapticsKey) as? Bool) ?? true }
        set { UserDefaults.standard.set(newValue, forKey: hapticsKey) }
    }

    /// Push persisted values into the live singletons.
    @MainActor
    static func applyAll() {
        MusicManager.shared.applyUserVolume(musicVolume)
        SFXManager.shared.targetVolume = sfxVolume
        HapticsManager.shared.enabled = hapticsEnabled
    }
}

// MARK: - Settings Sheet

struct SettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var music: Float = PlayerSettings.musicVolume
    @State private var sfx: Float = PlayerSettings.sfxVolume
    @State private var haptics: Bool = PlayerSettings.hapticsEnabled
    @State private var tipsReset = false

    var body: some View {
        ZStack {
            Color(hex: "070710").ignoresSafeArea()
            VStack(spacing: 22) {
                HStack {
                    Text("SETTINGS")
                        .font(.system(size: 18, weight: .black, design: .monospaced))
                        .tracking(3)
                        .foregroundColor(Color(hex: "00FFCC"))
                    Spacer()
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.white.opacity(0.6))
                    }
                }

                sliderRow(label: "MUSIC", icon: "music.note", value: $music,
                          tint: "B080FF") { v in
                    PlayerSettings.musicVolume = v
                    MusicManager.shared.applyUserVolume(v)
                }
                sliderRow(label: "SFX", icon: "speaker.wave.2.fill", value: $sfx,
                          tint: "00DDFF") { v in
                    PlayerSettings.sfxVolume = v
                    SFXManager.shared.targetVolume = v
                    SFXManager.shared.play("hit_metal", volume: v * 0.8)   // audible sample
                }

                Toggle(isOn: $haptics) {
                    HStack(spacing: 8) {
                        Image(systemName: "iphone.radiowaves.left.and.right")
                            .foregroundColor(Color(hex: "00FF88"))
                        Text("HAPTICS")
                            .font(.system(size: 13, weight: .black, design: .monospaced))
                            .tracking(2)
                            .foregroundColor(.white)
                    }
                }
                .tint(Color(hex: "00FF88"))
                .onChange(of: haptics) { on in
                    PlayerSettings.hapticsEnabled = on
                    HapticsManager.shared.enabled = on
                    if on { HapticsManager.shared.selectAffirm() }
                }

                // Toggles both ways: arming a replay used to be irreversible,
                // and the disabled state also lied after reopening Settings
                // because it tracked @State rather than the stored flags.
                Button(action: {
                    if tipsReset {
                        TutorialCoach.shared.markAllSeen()
                    } else {
                        TutorialCoach.shared.resetAll()
                    }
                    tipsReset.toggle()
                    HapticsManager.shared.buttonTap()
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: tipsReset ? "checkmark.circle" : "questionmark.circle")
                        Text(tipsReset ? "TIPS WILL REPLAY — TAP TO CANCEL" : "REPLAY TUTORIAL TIPS")
                            .tracking(1)
                    }
                    .font(.system(size: 12, weight: .black, design: .monospaced))
                    .foregroundColor(tipsReset ? Color(hex: "00FF88") : .white.opacity(0.85))
                    .frame(maxWidth: .infinity)
                    .frame(height: 42)
                    .overlay(RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.35), lineWidth: 1))
                }
                .onAppear { tipsReset = TutorialCoach.shared.anyUnseen }

                Spacer()

                Text("HEXWIRE")
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .tracking(4)
                    .foregroundColor(.white.opacity(0.25))
            }
            .padding(24)
        }
        .presentationDetents([.medium])
    }

    @ViewBuilder
    private func sliderRow(label: String, icon: String, value: Binding<Float>,
                           tint: String, onChange: @escaping (Float) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: icon).foregroundColor(Color(hex: tint))
                Text(label)
                    .font(.system(size: 13, weight: .black, design: .monospaced))
                    .tracking(2)
                    .foregroundColor(.white)
                Spacer()
                Text("\(Int(value.wrappedValue * 100))%")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(hex: tint))
            }
            Slider(value: Binding(
                get: { value.wrappedValue },
                set: { v in value.wrappedValue = v; onChange(v) }
            ), in: 0...1)
            .tint(Color(hex: tint))
        }
    }
}
