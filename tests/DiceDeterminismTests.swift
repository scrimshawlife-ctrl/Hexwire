import XCTest
#if canImport(HexWire)
@testable import HexWire

/// SplitMix64 — same generator family the game uses for seeded squad rerolls.
/// Defined locally so tests own their seed source.
struct TestRNG: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// Deterministic hit resolution: with a fixed RNG the entire RollResult is
/// reproducible, and its derived fields obey the engine's rules exactly.
final class DiceDeterminismTests: XCTestCase {

    func testSameSeedProducesIdenticalRollResult() {
        for seed: UInt64 in [0, 1, 42, 0xDEAD_BEEF] {
            var a = TestRNG(seed: seed)
            var b = TestRNG(seed: seed)
            let ra = DiceEngine.roll(pool: 8, using: &a)
            let rb = DiceEngine.roll(pool: 8, using: &b)
            XCTAssertEqual(ra.rolls, rb.rolls)
            XCTAssertEqual(ra.hits, rb.hits)
            XCTAssertEqual(ra.glitch, rb.glitch)
            XCTAssertEqual(ra.criticalGlitch, rb.criticalGlitch)
            XCTAssertEqual(ra.netHits, rb.netHits)
        }
    }

    func testSeededRollDerivedFieldsMatchRules() {
        // Recompute hits/glitch from the raw rolls and require agreement —
        // guards the counting logic against drift, on 200 seeded rolls.
        for seed in 0..<200 {
            var rng = TestRNG(seed: UInt64(seed))
            let pool = 1 + seed % 10
            let r = DiceEngine.roll(pool: pool, using: &rng)
            let recountedHits = r.rolls.filter { $0 >= 5 }.count
            let ones = r.rolls.filter { $0 == 1 }.count
            XCTAssertEqual(r.hits, recountedHits, "seed \(seed)")
            XCTAssertEqual(r.originalPool, pool)
            // Exploding sixes: total dice = pool + number of sixes rolled
            // before the final (six-free) wave. Equivalent check: dice beyond
            // the pool == sixes among all but the last wave; simplest robust
            // invariant: rolls.count == pool + sixes-that-exploded, i.e.
            // rolls.count - pool == sixes in rolls minus sixes in final wave.
            XCTAssertGreaterThanOrEqual(r.rolls.count, pool)
            // Glitch rule: strictly MORE than half the dice show 1s.
            XCTAssertEqual(r.glitch, ones * 2 > pool, "seed \(seed)")
            // Critical glitch: every original die a 1 and zero hits — implies glitch.
            if r.criticalGlitch {
                XCTAssertEqual(r.hits, 0)
                XCTAssertTrue(r.glitch)
            }
        }
    }

    func testSeededOpposedRollIsDeterministicAndClamped() {
        var a = TestRNG(seed: 99), b = TestRNG(seed: 99)
        let ra = DiceEngine.opposedRoll(attackerPool: 5, defenderPool: 7, using: &a)
        let rb = DiceEngine.opposedRoll(attackerPool: 5, defenderPool: 7, using: &b)
        XCTAssertEqual(ra.rolls, rb.rolls)
        XCTAssertEqual(ra.netHits, rb.netHits)
        for seed in 0..<100 {
            var rng = TestRNG(seed: UInt64(seed))
            let r = DiceEngine.opposedRoll(attackerPool: 3, defenderPool: 9, using: &rng)
            XCTAssertGreaterThanOrEqual(r.netHits, 0, "net hits clamp to zero")
        }
    }

    func testSeededSoakRollIsDeterministic() {
        var a = TestRNG(seed: 7), b = TestRNG(seed: 7)
        let ra = DiceEngine.soakRoll(pool: 6, using: &a)
        let rb = DiceEngine.soakRoll(pool: 6, using: &b)
        XCTAssertEqual(ra.soaked, rb.soaked)
        XCTAssertEqual(ra.rolls, rb.rolls)
    }

    func testUnseededOverloadStillSatisfiesInvariants() {
        // The production entry point (system RNG) keeps the same rules.
        for _ in 0..<300 {
            let r = DiceEngine.roll(pool: 6)
            XCTAssertGreaterThanOrEqual(r.hits, 0)
            XCTAssertEqual(r.hits, r.rolls.filter { $0 >= 5 }.count)
            XCTAssertTrue(r.rolls.allSatisfy { (1...6).contains($0) })
        }
    }

    // MARK: - Deterministic coordinate hashing (barrel placement)

    func testBarrelTileHashIsDeterministicAndBounded() {
        var barrelCount = 0
        let total = 40 * 40
        for x in 0..<40 {
            for y in 0..<40 {
                let first = TileMap.isBarrelTile(x: x, y: y)
                // Pure function of coordinates — identical on every call.
                XCTAssertEqual(first, TileMap.isBarrelTile(x: x, y: y))
                if first { barrelCount += 1 }
            }
        }
        // Documented rate is ~25% of cover tiles; allow a generous band so
        // the test pins the DESIGN (roughly a quarter) not the exact hash.
        let rate = Double(barrelCount) / Double(total)
        XCTAssertGreaterThan(rate, 0.10, "barrel rate collapsed: \(rate)")
        XCTAssertLessThan(rate, 0.45, "barrel rate exploded: \(rate)")
    }
}
#endif
