import Foundation
import AVFoundation

/// Multi-voice 8-bit audio engine.
///
/// Generates square / triangle / noise PCM at runtime — no audio asset files.
/// Three concurrent voices: a square-wave LEAD line, a triangle-wave BASS
/// line one octave down, and a NOISE drum kick on every fourth step. Plus a
/// dedicated SFX channel for one-shot blips (move / win / loss / bail / chaser
/// alert) so SFX never interrupts the music.
///
/// The melody is an A-minor cyberpunk loop — moody, propulsive, sits well
/// underneath gameplay tension. A quick 1-bar fill plays on stage transitions.
@MainActor
final class ChiptunePlayer {

    // MARK: - Engine

    private let engine = AVAudioEngine()
    private let leadPlayer = AVAudioPlayerNode()
    private let bassPlayer = AVAudioPlayerNode()
    private let drumPlayer = AVAudioPlayerNode()
    private let sfxPlayer  = AVAudioPlayerNode()
    private let format: AVAudioFormat

    private var melodyTimer: Timer?
    private var melodyStep: Int = 0
    private var isStarted: Bool = false

    // MARK: - Composition

    /// 32-step main loop. -1 = rest, otherwise = MIDI-style note index relative
    /// to A2 (110 Hz). The LEAD plays the upper line; BASS plays the lower
    /// rhythm; KICK fires on every 4th step. Patterns are ARCing — descend
    /// into the verse, climb to a hook, loop. Reads as a tense intrusion theme.
    private static let leadPattern: [Int] = [
        // 4 bars, 8 steps each (32 total)
        12, -1, 15, 17,  19, -1, 17, 15,  // bar 1: A4→C5→D5→E5...
        14, -1, 17, 19,  20, -1, 19, 17,  // bar 2: high climb
        12, -1, 10, 12,  15, -1, 14, 12,  // bar 3: relaxed
        10, -1, 12, 14,  15, -1, 17, 19,  // bar 4: climb back to top
    ]
    private static let bassPattern: [Int] = [
        0, -1,  0,  0,   3, -1,  3,  3,   // bar 1
        5, -1,  5,  5,   3, -1,  3,  3,   // bar 2
        0, -1,  0,  0,  -2, -1, -2, -2,   // bar 3
        3, -1,  3,  3,   5, -1,  7,  7,   // bar 4
    ]
    private static let kickPattern: [Bool] = [
        true, false, false, false,  true, false, false, false,
        true, false, false, false,  true, false, false, false,
        true, false, false, false,  true, false, false, false,
        true, false, false, false,  true, false, true,  true,
    ]
    /// Optional fill — a stage-transition flourish (8 quick notes).
    private static let fillPattern: [Int] = [12, 15, 17, 19, 20, 19, 17, 15]

    // MARK: - Init

    init?() {
        let fmt = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                sampleRate: 44100,
                                channels: 1,
                                interleaved: false)
        guard let fmt else { return nil }
        format = fmt

        engine.attach(leadPlayer)
        engine.attach(bassPlayer)
        engine.attach(drumPlayer)
        engine.attach(sfxPlayer)
        engine.connect(leadPlayer, to: engine.mainMixerNode, format: format)
        engine.connect(bassPlayer, to: engine.mainMixerNode, format: format)
        engine.connect(drumPlayer, to: engine.mainMixerNode, format: format)
        engine.connect(sfxPlayer,  to: engine.mainMixerNode, format: format)

        // Match MusicManager.targetVolume so the chiptune mini-game music
        // sits at the same loudness as the mission soundtrack we just
        // ducked. Without this the chiptune was running at AVAudioPlayer-
        // Node default (1.0) and felt much louder than everything else.
        // 0.397 = 0.4675 × 0.85 — another −15% (2026-05-10) so mini-game
        // chiptune sits comfortably under SFX feedback on iPhone playback.
        leadPlayer.volume = 0.397
        bassPlayer.volume = 0.397
        drumPlayer.volume = 0.397
        sfxPlayer.volume  = 0.397

        do {
            // .playback so silent-switch doesn't mute the chiptune.
            try AVAudioSession.sharedInstance().setCategory(.playback,
                                                            mode: .default,
                                                            options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            try engine.start()
            leadPlayer.play()
            bassPlayer.play()
            drumPlayer.play()
            sfxPlayer.play()
            isStarted = true
        } catch {
            isStarted = false
            return nil
        }
    }

    // MARK: - Public API

    func startMelody() {
        guard isStarted else { return }
        melodyTimer?.invalidate()
        melodyStep = 0
        // ~150 BPM sixteenths → 100ms/step. Tight enough to feel propulsive
        // without stepping on player input.
        let timer = Timer(timeInterval: 0.10, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tickMelody() }
        }
        RunLoop.main.add(timer, forMode: .common)
        melodyTimer = timer
    }

    /// Trigger the 1-bar transition fill at the next step boundary.
    func playStageFill() {
        guard isStarted else { return }
        Task { @MainActor in
            for note in ChiptunePlayer.fillPattern {
                let freq = midiToFreq(note + 24)   // up two octaves for emphasis
                if let buf = makeBuffer(freq: freq, duration: 0.08, volume: 0.22, wave: .square) {
                    await sfxPlayer.scheduleBuffer(buf, at: nil, options: [])
                }
                try? await Task.sleep(nanoseconds: 80_000_000)
            }
        }
    }

    func stop() {
        melodyTimer?.invalidate()
        melodyTimer = nil
        leadPlayer.stop()
        bassPlayer.stop()
        drumPlayer.stop()
        sfxPlayer.stop()
        engine.stop()
        isStarted = false
    }

    // MARK: - SFX presets

    /// Short low blip on player move.
    func sfxMove() {
        playSFX(freq: 220, duration: 0.04, volume: 0.10, wave: .square)
    }

    /// Quick warning chirp when a chaser is adjacent to the player.
    func sfxChaserNear() {
        playSFX(freq: 660, duration: 0.05, volume: 0.06, wave: .square)
    }

    /// Triumphant rising arpeggio — runner reached the data core.
    func sfxWin() {
        Task { @MainActor in
            playSFX(freq: 523.25, duration: 0.10, volume: 0.20, wave: .square)
            try? await Task.sleep(nanoseconds: 110_000_000)
            playSFX(freq: 659.26, duration: 0.10, volume: 0.20, wave: .square)
            try? await Task.sleep(nanoseconds: 110_000_000)
            playSFX(freq: 783.99, duration: 0.10, volume: 0.20, wave: .square)
            try? await Task.sleep(nanoseconds: 110_000_000)
            playSFX(freq: 1046.50, duration: 0.30, volume: 0.22, wave: .square)
        }
    }

    /// Descending failure tone with a sour minor second on the tail.
    func sfxLose() {
        Task { @MainActor in
            playSFX(freq: 220,    duration: 0.12, volume: 0.20, wave: .square)
            try? await Task.sleep(nanoseconds: 130_000_000)
            playSFX(freq: 174.61, duration: 0.12, volume: 0.20, wave: .square)
            try? await Task.sleep(nanoseconds: 130_000_000)
            playSFX(freq: 138.59, duration: 0.30, volume: 0.22, wave: .square)
        }
    }

    /// Short staccato for the BAIL button.
    func sfxBail() {
        Task { @MainActor in
            playSFX(freq: 196,    duration: 0.06, volume: 0.16, wave: .square)
            try? await Task.sleep(nanoseconds: 70_000_000)
            playSFX(freq: 130.81, duration: 0.10, volume: 0.18, wave: .square)
        }
    }

    // MARK: - Mini-game-specific SFX

    /// Lane-runner: jumping over a firewall. Two-tone rising blip.
    func sfxJump() {
        Task { @MainActor in
            playSFX(freq: 440, duration: 0.04, volume: 0.16, wave: .square)
            try? await Task.sleep(nanoseconds: 40_000_000)
            playSFX(freq: 660, duration: 0.05, volume: 0.16, wave: .square)
        }
    }

    /// Lane-runner: collecting a data shard. Bright ascending chime.
    func sfxCollect() {
        Task { @MainActor in
            playSFX(freq: 880, duration: 0.04, volume: 0.20, wave: .square)
            try? await Task.sleep(nanoseconds: 40_000_000)
            playSFX(freq: 1320, duration: 0.06, volume: 0.20, wave: .square)
        }
    }

    /// Lane-runner: switching lanes. Quick whoosh.
    func sfxLaneSwitch() {
        playSFX(freq: 330, duration: 0.04, volume: 0.10, wave: .square)
    }

    /// Generic damage tone — noise burst with low pitch.
    func sfxHit() {
        playSFX(freq: 110, duration: 0.10, volume: 0.20, wave: .noise)
    }

    /// Cypher-cracker: a ring locked in. Two-tone success.
    func sfxRingLock() {
        Task { @MainActor in
            playSFX(freq: 523, duration: 0.06, volume: 0.20, wave: .square)
            try? await Task.sleep(nanoseconds: 60_000_000)
            playSFX(freq: 784, duration: 0.10, volume: 0.20, wave: .square)
        }
    }

    /// Cypher-cracker: missed alignment. Sour low buzz.
    func sfxRingMiss() {
        playSFX(freq: 165, duration: 0.10, volume: 0.18, wave: .square)
    }

    /// Packet-router: hopping the packet to a new node.
    func sfxNodeHop() {
        playSFX(freq: 420, duration: 0.04, volume: 0.12, wave: .square)
    }

    /// Packet-router: ICE program close to the packet.
    func sfxICEAlert() {
        Task { @MainActor in
            playSFX(freq: 220, duration: 0.06, volume: 0.10, wave: .square)
            try? await Task.sleep(nanoseconds: 80_000_000)
            playSFX(freq: 165, duration: 0.06, volume: 0.10, wave: .square)
        }
    }

    // MARK: - Internals

    private enum Wave { case square, triangle, noise }

    /// Convert a note offset (semitones above A2 = 110 Hz) to a frequency in Hz.
    private func midiToFreq(_ semitones: Int) -> Double {
        // A2 = 110 Hz. 12 semitones per octave.
        return 110.0 * pow(2.0, Double(semitones) / 12.0)
    }

    private func tickMelody() {
        guard isStarted else { return }
        let i = melodyStep % ChiptunePlayer.leadPattern.count
        melodyStep += 1

        // LEAD voice — square wave, low volume so it doesn't drown gameplay.
        let leadNote = ChiptunePlayer.leadPattern[i]
        if leadNote >= -12, let buf = makeBuffer(
            freq: midiToFreq(leadNote + 12),    // +12 → up an octave (around A3-A4)
            duration: 0.09,
            volume: 0.07,
            wave: .square
        ) {
            leadPlayer.scheduleBuffer(buf, at: nil, options: [], completionHandler: nil)
        }

        // BASS voice — triangle wave, an octave below lead range.
        let bassNote = ChiptunePlayer.bassPattern[i]
        if bassNote >= -12, let buf = makeBuffer(
            freq: midiToFreq(bassNote),
            duration: 0.09,
            volume: 0.10,
            wave: .triangle
        ) {
            bassPlayer.scheduleBuffer(buf, at: nil, options: [], completionHandler: nil)
        }

        // KICK drum — short noise burst on the downbeat.
        if ChiptunePlayer.kickPattern[i],
           let buf = makeBuffer(freq: 80, duration: 0.05, volume: 0.16, wave: .noise) {
            drumPlayer.scheduleBuffer(buf, at: nil, options: [], completionHandler: nil)
        }
    }

    private func playSFX(freq: Double, duration: TimeInterval, volume: Float, wave: Wave) {
        guard isStarted else { return }
        guard let buf = makeBuffer(freq: freq, duration: duration, volume: volume, wave: wave) else { return }
        sfxPlayer.scheduleBuffer(buf, at: nil, options: [], completionHandler: nil)
    }

    /// Synthesize a PCM buffer for one tone.  Square / triangle for melody +
    /// SFX; "noise" is a low-passed white-noise burst for the kick drum.
    /// Adds a quick attack + decay envelope so notes don't click on/off.
    private func makeBuffer(freq: Double, duration: TimeInterval, volume: Float, wave: Wave) -> AVAudioPCMBuffer? {
        let frameCount = AVAudioFrameCount(format.sampleRate * duration)
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return nil }
        buffer.frameLength = frameCount
        guard let samples = buffer.floatChannelData?[0] else { return nil }

        let sampleRate = format.sampleRate
        let period = sampleRate / max(freq, 1.0)
        let attackSamples = Int(min(0.005, duration / 4) * sampleRate)
        let decaySamples  = Int(min(0.020, duration / 3) * sampleRate)
        let total = Int(frameCount)

        // Cheap 1-pole low-pass for the noise voice (gives the kick body
        // instead of pure hiss). Single previous-sample state.
        var lp: Float = 0
        let lpAlpha: Float = 0.18

        for i in 0..<total {
            let raw: Float
            switch wave {
            case .square:
                let phase = Double(i).truncatingRemainder(dividingBy: period) / period
                raw = phase < 0.5 ? 1.0 : -1.0
            case .triangle:
                let phase = Double(i).truncatingRemainder(dividingBy: period) / period
                let p = phase * 2.0
                raw = Float(p < 1.0 ? (p * 2.0 - 1.0) : (3.0 - p * 2.0))
            case .noise:
                let n = Float.random(in: -1...1)
                lp = lp + lpAlpha * (n - lp)
                // Apply a falling pitch sweep so the kick "thumps" rather than hisses
                let sweep = Float(1.0 - Double(i) / Double(total))
                raw = lp * (0.6 + 0.4 * sweep)
            }

            // Envelope (linear attack + decay)
            let env: Float
            if i < attackSamples && attackSamples > 0 {
                env = Float(i) / Float(attackSamples)
            } else if i > total - decaySamples && decaySamples > 0 {
                env = Float(total - i) / Float(decaySamples)
            } else {
                env = 1.0
            }
            samples[i] = raw * volume * env
        }
        return buffer
    }
}
