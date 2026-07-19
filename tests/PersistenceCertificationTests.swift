import XCTest
#if canImport(HexWire)
@testable import HexWire

/// WP7 persistence & migration certification — the cases WP2's economy suite
/// didn't reach: fresh-install defaults, missing-field (pre-upgrade) blob
/// decode, the corrupt→backup recovery chain, the chase-completion backfill
/// migration, and a full app-upgrade simulation across the key rename.
final class PersistenceCertificationTests: XCTestCase {

    private let touchedKeys = [
        "HexWire.MissionStats.v1", "HexWire.MissionStats.v1.lastGood",
        "HexWire.PlayerNuyen.v1", "HexWire.PaidThisRun.v1",
        "HexWire.Roster.v1", "HexWire.Roster.v1.lastGood",
        "HexWire.NGPlusTier.v1", "HexWire.FactionAttention.v1",
        "HexWire.Migration.KeyRename.v1", "HexWire.Migration.ChaseBackfill.v1",
        "ShadowrunGame.MissionStats.v1", "ShadowrunGame.PlayerNuyen.v1",
        "ShadowrunGame.Migration.ChaseBackfill.v1",
    ]
    private var snapshot: [String: Any] = [:]

    override func setUp() {
        super.setUp()
        snapshot = [:]
        for key in touchedKeys {
            if let v = UserDefaults.standard.object(forKey: key) { snapshot[key] = v }
        }
    }

    override func tearDown() {
        MissionStatsStore.shared.resetAll()
        for key in touchedKeys { UserDefaults.standard.removeObject(forKey: key) }
        for (key, v) in snapshot { UserDefaults.standard.set(v, forKey: key) }
        super.tearDown()
    }

    // MARK: - 1. Fresh-install defaults

    func testFreshInstallDefaultsAreSafe() {
        for key in touchedKeys { UserDefaults.standard.removeObject(forKey: key) }
        MissionStatsStore.shared.resetAll()

        XCTAssertEqual(MissionStatsStore.shared.record(for: "Mission001"), .empty)
        XCTAssertEqual(MissionStatsStore.shared.playerNuyen, 0)
        XCTAssertEqual(MissionStatsStore.shared.missionsCompleted, 0)
        XCTAssertEqual(MissionStatsStore.shared.loadFactionAttention(),
                       [.corp: 0, .gang: 0, .unknown: 0])
        XCTAssertEqual(NGPlusStore.shared.tier >= 0, true)
        XCTAssertEqual(RosterStore.shared.loadCanonical().count,
                       Character.allRunners.count,
                       "fresh install must yield the default roster")
        XCTAssertNil(MissionStatsStore.decodeRecords(live: nil, backup: nil),
                     "no data → nil → caller keeps in-memory defaults")
    }

    // MARK: - 2. Pre-upgrade blob missing a later-added field

    /// `bestMiniGameScore` was added to MissionRecord after early saves
    /// shipped. A blob written before that field existed must still decode
    /// (field defaults to 0) — otherwise every veteran install's completion
    /// records are silently wiped on upgrade.
    func testLegacyRecordBlobWithoutMiniGameFieldStillDecodes() throws {
        let legacyJSON = """
        {"Mission001": {"bestScore": 1800, "attempts": 3,
                        "lastCompletedAt": 767000000.0}}
        """
        let decoded = MissionStatsStore.decodeRecords(
            live: Data(legacyJSON.utf8), backup: nil)
        let rec = try XCTUnwrap(decoded?["Mission001"],
                                "pre-miniGame-field blob must decode, not wipe records")
        XCTAssertEqual(rec.bestScore, 1800)
        XCTAssertEqual(rec.attempts, 3)
        XCTAssertTrue(rec.completed)
        XCTAssertEqual(rec.bestMiniGameScore, 0, "missing field defaults, not fails")
    }

    /// Same shape for a hypothetical FUTURE field: unknown keys must be ignored.
    func testRecordBlobWithUnknownExtraFieldDecodes() throws {
        let futureJSON = """
        {"Mission001": {"bestScore": 100, "attempts": 1, "lastCompletedAt": null,
                        "bestMiniGameScore": 5, "someFutureField": true}}
        """
        let decoded = MissionStatsStore.decodeRecords(live: Data(futureJSON.utf8), backup: nil)
        XCTAssertEqual(decoded?["Mission001"]?.bestScore, 100)
    }

    // MARK: - 3. Corrupt → backup recovery chain (now directly testable)

    func testDecodeRecordsRecoveryChain() throws {
        let good = try JSONEncoder().encode(
            ["Mission002": MissionRecord(bestScore: 900, attempts: 1,
                                         lastCompletedAt: Date(), bestMiniGameScore: 0)])
        let corrupt = Data("not json".utf8)

        XCTAssertEqual(MissionStatsStore.decodeRecords(live: good, backup: nil)?["Mission002"]?.bestScore, 900,
                       "healthy live blob wins")
        XCTAssertEqual(MissionStatsStore.decodeRecords(live: corrupt, backup: good)?["Mission002"]?.bestScore, 900,
                       "corrupt live falls back to last-good")
        XCTAssertNil(MissionStatsStore.decodeRecords(live: corrupt, backup: corrupt),
                     "corrupt live + corrupt backup → nil (defaults), never a crash")
        XCTAssertNil(MissionStatsStore.decodeRecords(live: nil, backup: good),
                     "backup is only consulted when a live blob EXISTS but is corrupt")
    }

    // MARK: - 4. Chase-completion backfill migration

    func testChaseBackfillMigratesEligibleFootprintExactlyOnce() {
        MissionStatsStore.shared.resetAll()
        UserDefaults.standard.removeObject(forKey: "HexWire.Migration.ChaseBackfill.v1")
        // Eligible footprint: M1–M3 completed, chase record absent.
        for id in ["Mission001", "Mission002", "Mission003"] {
            MissionStatsStore.shared.recordVictory(missionId: id, score: 1000)
        }
        XCTAssertFalse(MissionStatsStore.shared.record(for: "Mission003_5").completed)

        MissionStatsStore.shared.migrateBackfillChaseCompletion()
        let rec = MissionStatsStore.shared.record(for: "Mission003_5")
        XCTAssertTrue(rec.completed, "eligible veteran gets the backfilled completion")
        XCTAssertGreaterThanOrEqual(rec.attempts, 1)
        XCTAssertFalse(MissionStatsStore.shared.paidThisRun.contains("Mission003_5"),
                       "backfill must NOT mark the chase as paid (make-good payout stays claimable)")
        XCTAssertTrue(UserDefaults.standard.bool(forKey: "HexWire.Migration.ChaseBackfill.v1"))

        // Flag latched: wiping the record and re-running must NOT backfill again.
        MissionStatsStore.shared.resetAll()
        for id in ["Mission001", "Mission002", "Mission003"] {
            MissionStatsStore.shared.recordVictory(missionId: id, score: 1000)
        }
        MissionStatsStore.shared.migrateBackfillChaseCompletion()
        XCTAssertFalse(MissionStatsStore.shared.record(for: "Mission003_5").completed,
                       "one-shot migration must never replay after its flag is set")
    }

    func testChaseBackfillIgnoresIneligibleFootprint() {
        MissionStatsStore.shared.resetAll()
        UserDefaults.standard.removeObject(forKey: "HexWire.Migration.ChaseBackfill.v1")
        // Only M1 done — player never reached the chase; nothing to make good.
        MissionStatsStore.shared.recordVictory(missionId: "Mission001", score: 1000)
        MissionStatsStore.shared.migrateBackfillChaseCompletion()
        XCTAssertFalse(MissionStatsStore.shared.record(for: "Mission003_5").completed,
                       "ineligible installs must not be gifted a completion")
        XCTAssertTrue(UserDefaults.standard.bool(forKey: "HexWire.Migration.ChaseBackfill.v1"),
                      "flag still latches so the check never re-runs")
    }

    // MARK: - 5. Full app-upgrade simulation (rename + old-format blob)

    /// A veteran install: data under the OLD "ShadowrunGame.*" keys, records in
    /// the OLD format (no bestMiniGameScore). After the rebrand migration +
    /// decode, everything must survive.
    func testUpgradeFromLegacyInstallPreservesProgressEndToEnd() throws {
        let d = UserDefaults.standard
        for key in touchedKeys { d.removeObject(forKey: key) }
        let oldBlob = Data("""
        {"Mission001": {"bestScore": 2200, "attempts": 4, "lastCompletedAt": 767000000.0}}
        """.utf8)
        d.set(oldBlob, forKey: "ShadowrunGame.MissionStats.v1")
        d.set(31_337, forKey: "ShadowrunGame.PlayerNuyen.v1")

        StorageMigration.migrateLegacyKeysIfNeeded()

        XCTAssertEqual(d.integer(forKey: "HexWire.PlayerNuyen.v1"), 31_337,
                       "wallet survives the key rename")
        let migrated = MissionStatsStore.decodeRecords(
            live: d.data(forKey: "HexWire.MissionStats.v1"), backup: nil)
        let rec = try XCTUnwrap(migrated?["Mission001"],
                                "old-format records must survive rename + decode")
        XCTAssertEqual(rec.bestScore, 2200)
        XCTAssertEqual(rec.attempts, 4)
        XCTAssertTrue(rec.completed)
    }

    // MARK: - 6. Interrupted lifecycle (partial key writes)

    func testPartialKeyStateLoadsIndependently() {
        let d = UserDefaults.standard
        for key in touchedKeys { d.removeObject(forKey: key) }
        // Simulate an interrupt between the two writes of save(): wallet
        // landed, records didn't. Each key must load independently.
        d.set(4_500, forKey: "HexWire.PlayerNuyen.v1")
        XCTAssertNil(MissionStatsStore.decodeRecords(
            live: d.data(forKey: "HexWire.MissionStats.v1"),
            backup: d.data(forKey: "HexWire.MissionStats.v1.lastGood")),
            "missing records blob → defaults")
        XCTAssertEqual(d.integer(forKey: "HexWire.PlayerNuyen.v1"), 4_500,
                       "wallet is not held hostage by the records blob")
    }

    // MARK: - 7. Faction attention raw round-trip

    @MainActor
    func testFactionAttentionPersistsAndRestoresUnknownKeysSafely() {
        MissionStatsStore.shared.saveFactionAttention([.corp: 3, .gang: 1, .unknown: 0])
        XCTAssertEqual(MissionStatsStore.shared.loadFactionAttention(),
                       [.corp: 3, .gang: 1, .unknown: 0])
        // A future faction raw-value in the stored dict must not break loading.
        var raw = UserDefaults.standard.dictionary(forKey: "HexWire.FactionAttention.v1") as? [String: Int] ?? [:]
        raw["futureFaction"] = 9
        UserDefaults.standard.set(raw, forKey: "HexWire.FactionAttention.v1")
        let loaded = MissionStatsStore.shared.loadFactionAttention()
        XCTAssertEqual(loaded[.corp], 3, "known factions still load")
        MissionStatsStore.shared.resetFactionAttention()
    }
}
#endif
