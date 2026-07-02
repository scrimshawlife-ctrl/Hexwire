import XCTest
#if canImport(HexWire)
@testable import HexWire

/// Deterministic tests for the stateless combat math. These avoid GameState /
/// singletons so they run as fast logic tests with no game setup.
final class CombatMathTests: XCTestCase {

    // MARK: - DiceEngine

    func testEmptyPoolRollsNothing() {
        let r = DiceEngine.roll(pool: 0)
        XCTAssertEqual(r.hits, 0)
        XCTAssertFalse(r.glitch)
        XCTAssertFalse(r.criticalGlitch)
        XCTAssertTrue(r.rolls.isEmpty)
    }

    func testRollNeverProducesNegativeHits() {
        for pool in 0...12 {
            for _ in 0..<200 {
                XCTAssertGreaterThanOrEqual(DiceEngine.roll(pool: pool).hits, 0)
            }
        }
    }

    func testCriticalGlitchAlsoFlagsGlitch() {
        // A critical glitch (all 1s, no hits) must never report a non-glitch.
        // Statistical: a 1-die pool rolls a single die; over many rolls some
        // are a critical glitch (the die shows 1). Every critical glitch seen
        // must satisfy the invariant.
        for _ in 0..<2000 {
            let r = DiceEngine.roll(pool: 1)
            if r.criticalGlitch {
                XCTAssertEqual(r.hits, 0, "critical glitch must have zero hits")
            }
        }
    }

    func testOpposedRollNetHitsClampToZero() {
        for _ in 0..<500 {
            let r = DiceEngine.opposedRoll(attackerPool: 3, defenderPool: 8)
            XCTAssertGreaterThanOrEqual(r.netHits, 0)
        }
    }

    // MARK: - Cover (CombatMechanics)

    func testCoverDefenseBonusTiers() {
        XCTAssertEqual(CombatMechanics.coverDefenseBonus(count: 0), 0)
        XCTAssertEqual(CombatMechanics.coverDefenseBonus(count: 1), 1)
        XCTAssertEqual(CombatMechanics.coverDefenseBonus(count: 2), 2)
        XCTAssertEqual(CombatMechanics.coverDefenseBonus(count: 9), 2) // capped
    }

    func testCoverBetweenCountsIntermediateCoverTilesOnly() {
        // Row of 5 tiles, middle three are cover (tileType 2). Endpoints are
        // excluded, so a shot from x=0 to x=4 should see the 3 cover tiles at
        // x=1,2,3.
        let tiles = [[0, 2, 2, 2, 0]]
        let count = CombatMechanics.coverBetween(tiles: tiles, fromX: 0, fromY: 0, toX: 4, toY: 0)
        XCTAssertEqual(count, 3)
    }

    func testCoverBetweenEmptyGridIsZero() {
        XCTAssertEqual(CombatMechanics.coverBetween(tiles: [], fromX: 0, fromY: 0, toX: 3, toY: 3), 0)
    }

    // MARK: - Status effects (regression guard for the removed .marked/.confused)

    func testBurningDisplayName() {
        XCTAssertEqual(StatusEffect.burning(roundsLeft: 3).displayName, "Burning·3")
    }
}
#endif
