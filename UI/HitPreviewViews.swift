import SwiftUI

// Extracted from CombatUI.swift (WP5 decomposition) — pure move.

// MARK: - Hit Preview Card

struct HitPreviewCard: View {
    let preview: CombatMechanics.HitPreview

    private var hitChancePct: Int { Int((preview.estimatedHitChance * 100).rounded()) }

    private var hitColor: Color {
        if preview.blocked               { return CombatTheme.textMuted }
        if preview.estimatedHitChance > 0.60 { return CombatTheme.accent }
        if preview.estimatedHitChance > 0.35 { return Color.yellow }
        return CombatTheme.enemyColor
    }

    var body: some View {
        Group {
            if preview.blocked {
                // Blocked state: LOS, range, or another hard pre-attack gate.
                HStack(spacing: 6) {
                    Text(preview.actionLabel)
                        .font(.system(size: 8, weight: .black, design: .monospaced))
                        .foregroundColor(.black)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(CombatTheme.enemyColor)
                        .cornerRadius(3)
                    Image(systemName: preview.reason == "Move adjacent first" ? "figure.walk.circle.fill" : "xmark.shield.fill")
                        .foregroundColor(CombatTheme.enemyColor)
                        .font(.system(size: 11))
                    Text(preview.reason == "Move adjacent first" ? "MELEE ONLY - MOVE ADJACENT" : "NO LOS - \(preview.reason ?? "blocked")")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(CombatTheme.enemyColor)
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(CombatTheme.panelBG)
                        .overlay(RoundedRectangle(cornerRadius: 6)
                            .stroke(CombatTheme.enemyColor.opacity(0.4), lineWidth: 1))
                )
            } else {
                // Normal preview state
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(preview.actionLabel)
                                .font(.system(size: 7, weight: .black, design: .monospaced))
                                .foregroundColor(.black)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(hitColor)
                                .cornerRadius(3)
                            Text(preview.weaponName.uppercased())
                                .font(.system(size: 7, weight: .bold, design: .monospaced))
                                .foregroundColor(CombatTheme.textMuted)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                        }
                        Text(preview.targetName.uppercased())
                            .font(.system(size: 10, weight: .black, design: .monospaced))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(width: 88, alignment: .leading)

                    Rectangle()
                        .fill(CombatTheme.secondary.opacity(0.5))
                        .frame(width: 1, height: 28)

                    // Hit chance %
                    VStack(spacing: 1) {
                        Text("HIT")
                            .font(.system(size: 7, weight: .black, design: .monospaced))
                            .foregroundColor(CombatTheme.textMuted)
                        Text("\(hitChancePct)%")
                            .font(.system(size: 15, weight: .black, design: .monospaced))
                            .foregroundColor(hitColor)
                    }

                    Rectangle()
                        .fill(CombatTheme.secondary.opacity(0.5))
                        .frame(width: 1, height: 28)

                    // Dice pools
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text("ATK")
                                .font(.system(size: 7, weight: .bold, design: .monospaced))
                                .foregroundColor(CombatTheme.textMuted)
                            Text("\(preview.attackPool)d6")
                                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                .foregroundColor(.white)
                        }
                        HStack(spacing: 4) {
                            Text("DEF")
                                .font(.system(size: 7, weight: .bold, design: .monospaced))
                                .foregroundColor(CombatTheme.textMuted)
                            Text("\(preview.defensePool)d6")
                                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                .foregroundColor(.white)
                            if preview.coverBonus > 0 {
                                Text("+\(preview.coverBonus)cov")
                                    .font(.system(size: 8, weight: .black, design: .monospaced))
                                    .foregroundColor(CombatTheme.gold)
                            }
                        }
                    }

                    Rectangle()
                        .fill(CombatTheme.secondary.opacity(0.5))
                        .frame(width: 1, height: 28)

                    // Estimated damage
                    VStack(spacing: 1) {
                        Text("DMG")
                            .font(.system(size: 7, weight: .black, design: .monospaced))
                            .foregroundColor(CombatTheme.textMuted)
                        Text("~\(Int(preview.estimatedDamage.rounded()))")
                            .font(.system(size: 15, weight: .black, design: .monospaced))
                            .foregroundColor(CombatTheme.damage)
                        Text("W\(preview.weaponDamage)")
                            .font(.system(size: 7, weight: .bold, design: .monospaced))
                            .foregroundColor(CombatTheme.textMuted)
                    }

                    Spacer()

                    // LOS checkmark
                    VStack(spacing: 1) {
                        Text("LOS")
                            .font(.system(size: 7, weight: .black, design: .monospaced))
                            .foregroundColor(CombatTheme.textMuted)
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundColor(CombatTheme.accent)
                    }

                    VStack(spacing: 1) {
                        Text("COST")
                            .font(.system(size: 7, weight: .black, design: .monospaced))
                            .foregroundColor(CombatTheme.textMuted)
                        Text("TURN")
                            .font(.system(size: 8, weight: .black, design: .monospaced))
                            .foregroundColor(CombatTheme.gold)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(CombatTheme.panelBG)
                        .overlay(RoundedRectangle(cornerRadius: 6)
                            .stroke(hitColor.opacity(0.45), lineWidth: 1))
                )
            }
        }
        .animation(.easeInOut(duration: 0.15), value: hitChancePct)
    }
}

struct HitPreviewStrip: View {
    let previews: [CombatMechanics.HitPreview]
    var notice: String? = nil

    private var targetName: String {
        previews.first?.targetName.uppercased() ?? "TARGET"
    }

    private var stripColor: Color {
        if previews.allSatisfy(\.blocked) { return CombatTheme.enemyColor }
        if previews.contains(where: { $0.estimatedHitChance > 0.60 }) { return CombatTheme.accent }
        if previews.contains(where: { $0.estimatedHitChance > 0.35 }) { return Color.yellow }
        return CombatTheme.enemyColor
    }

    var body: some View {
        HStack(spacing: 5) {
            if previews.isEmpty {
                Image(systemName: "arrowshape.turn.up.right.fill")
                    .font(.system(size: 10, weight: .black))
                    .foregroundColor(CombatTheme.gold)
                Text(notice ?? "END TURN")
                    .font(.system(size: 9, weight: .black, design: .monospaced))
                    .foregroundColor(CombatTheme.gold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 0)
            } else {
                HStack(spacing: 3) {
                    Text("TGT")
                        .font(.system(size: 7, weight: .black, design: .monospaced))
                        .foregroundColor(CombatTheme.textMuted)
                    Text(targetName)
                        .font(.system(size: 9, weight: .black, design: .monospaced))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                .frame(width: 72, alignment: .leading)

                ForEach(Array(previews.enumerated()), id: \.offset) { _, preview in
                    CompactHitPreviewPill(preview: preview)
                }

                Spacer(minLength: 0)

                HStack(spacing: 3) {
                    Image(systemName: notice == nil ? "checkmark.circle.fill" : "arrowshape.turn.up.right.fill")
                        .font(.system(size: 10))
                        .foregroundColor(notice == nil
                                         ? (previews.allSatisfy(\.blocked) ? CombatTheme.textMuted : CombatTheme.accent)
                                         : CombatTheme.gold)
                    Text(notice ?? "TURN")
                        .font(.system(size: 8, weight: .black, design: .monospaced))
                        .foregroundColor(CombatTheme.gold)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(CombatTheme.panelBG)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(stripColor.opacity(0.45), lineWidth: 1)
                )
        )
    }
}

private struct CompactHitPreviewPill: View {
    let preview: CombatMechanics.HitPreview

    private var hitChancePct: Int {
        Int((preview.estimatedHitChance * 100).rounded())
    }

    private var tint: Color {
        if preview.blocked { return CombatTheme.enemyColor }
        if preview.estimatedHitChance > 0.60 { return CombatTheme.accent }
        if preview.estimatedHitChance > 0.35 { return Color.yellow }
        return CombatTheme.enemyColor
    }

    private var blockedLabel: String {
        preview.reason == "Move adjacent first" ? "ADJ" : "NO LOS"
    }

    var body: some View {
        HStack(spacing: 3) {
            Text(preview.actionLabel)
                .font(.system(size: 7, weight: .black, design: .monospaced))
                .foregroundColor(.black)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(tint)
                .cornerRadius(3)

            if preview.blocked {
                Text(blockedLabel)
                    .font(.system(size: 8, weight: .black, design: .monospaced))
                    .foregroundColor(tint)
            } else {
                Text("\(hitChancePct)%")
                    .font(.system(size: 9, weight: .black, design: .monospaced))
                    .foregroundColor(tint)
                Text("~\(Int(preview.estimatedDamage.rounded()))")
                    .font(.system(size: 9, weight: .black, design: .monospaced))
                    .foregroundColor(CombatTheme.damage)
                Text("\(preview.attackPool)/\(preview.defensePool)")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(CombatTheme.textMuted)
                if preview.coverBonus > 0 {
                    Text("+\(preview.coverBonus)c")
                        .font(.system(size: 7, weight: .black, design: .monospaced))
                        .foregroundColor(CombatTheme.gold)
                }
            }
        }
        .lineLimit(1)
    }
}

// MARK: - CombatUI

