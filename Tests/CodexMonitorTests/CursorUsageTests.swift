import XCTest
import JavaScriptCore
@testable import CodexMonitor

final class CursorUsageTests: XCTestCase {
    private func summary(_ plan: String, end: String = "2026-11-03T12:00:00.000Z") throws -> CursorUsageParser.Limits? {
        try CursorUsageParser.parseSummary(Data("""
        {"billingCycleEnd":"\(end)","individualUsage":{"plan":\(plan)}}
        """.utf8))
    }

    func testTwoBucketsPreserveFractionalPercentAndBillingEnd() throws {
        let result = try XCTUnwrap(summary(#"{"autoPercentUsed":2.2,"apiPercentUsed":0.0,"totalPercentUsed":98}"#))
        XCTAssertEqual(result.cursorModels.precisePercentRemaining, 97.8, accuracy: 0.0001)
        XCTAssertEqual(result.otherModels.precisePercentRemaining, 100)
        XCTAssertEqual(result.cursorModels.resetText, "2026-11-03T12:00:00Z")
        XCTAssertEqual(result.otherModels.resetText, result.cursorModels.resetText)
    }

    func testFractionalPercentageIsNotFractionOfOne() throws {
        let result = try XCTUnwrap(summary(#"{"autoPercentUsed":0.36,"apiPercentUsed":99.1}"#))
        XCTAssertEqual(result.cursorModels.precisePercentRemaining, 99.64, accuracy: 0.0001)
        XCTAssertEqual(result.otherModels.precisePercentRemaining, 0.9, accuracy: 0.0001)
    }

    func testMissingBucketsAndBadDateAreUnavailable() throws {
        XCTAssertNil(try summary(#"{"totalPercentUsed":2.2}"#))
        XCTAssertNil(try summary(#"{"autoPercentUsed":2.2}"#))
        XCTAssertNil(try summary(#"{"autoPercentUsed":-2,"apiPercentUsed":0}"#))
        XCTAssertNil(try summary(#"{"autoPercentUsed":2,"apiPercentUsed":0}"#, end: "invalid"))
        XCTAssertNil(try CursorUsageParser.parseSummary(Data(#"{"teamUsage":{"pooled":{"used":20,"limit":100}}}"#.utf8)))
    }

    func testOverageClampsToZeroRemaining() throws {
        let result = try XCTUnwrap(summary(#"{"autoPercentUsed":123.4,"apiPercentUsed":100}"#))
        XCTAssertEqual(result.cursorModels.precisePercentRemaining, 0)
        XCTAssertEqual(result.otherModels.precisePercentRemaining, 0)
    }

    func testDaysAndHoursCountdownIncludingExpiredCycle() {
        let reset = "2026-11-03T12:00:00Z"
        let now = ISO8601DateFormatter().date(from: "2026-10-19T06:00:00Z")!
        XCTAssertEqual(ResetCountdownFormatter.countdown(from: reset, now: now, daysAndHoursOnly: true), "15d 6h")
        let end = ISO8601DateFormatter().date(from: reset)!
        XCTAssertEqual(ResetCountdownFormatter.countdown(from: reset, now: end.addingTimeInterval(-1800), daysAndHoursOnly: true), "<1h")
        XCTAssertEqual(ResetCountdownFormatter.countdown(from: reset, now: end.addingTimeInterval(3600), daysAndHoursOnly: true), "0d 0h")
    }

    @MainActor
    func testCompanionExportPreservesExistingFieldsAndAddsCursorBuckets() throws {
        let codex = UsageService(configuration: .codex)
        let claude = UsageService(configuration: .claude)
        let cursor = UsageService(configuration: .cursor)
        let limits = try XCTUnwrap(summary(#"{"autoPercentUsed":2.2,"apiPercentUsed":0}"#))
        cursor.fiveHourLimit = limits.cursorModels
        cursor.weeklyLimit = limits.otherModels
        cursor.authState = .authenticated
        let snapshot = QuotaStatusSnapshot(selectedUsageSource: .cursor, codexService: codex,
                                           claudeService: claude, cursorService: cursor)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot)) as? [String: Any])
        XCTAssertEqual(object["schemaVersion"] as? Int, 1)
        XCTAssertNotNil(object["codex"])
        XCTAssertNotNil(object["claude"])
        let exportedCursor = try XCTUnwrap(object["cursor"] as? [String: Any])
        let bucket = try XCTUnwrap(exportedCursor["cursorModels"] as? [String: Any])
        XCTAssertEqual(bucket["precisePercentRemaining"] as? Double, 97.8)
        XCTAssertEqual(bucket["resetAt"] as? String, limits.cursorModels.resetText)
        XCTAssertNotNil(exportedCursor["otherModels"])
    }

    func testOlderWidgetSnapshotsStillDecodeWithoutCursor() throws {
        let data = try JSONEncoder().encode(QuotaWidgetSnapshot.placeholder)
        let decoded = try JSONDecoder().decode(QuotaWidgetSnapshot.self, from: data)
        XCTAssertNil(decoded.cursor)
        XCTAssertEqual(decoded.codex, QuotaWidgetSnapshot.placeholder.codex)
    }

    // A minimal dashboard DOM fixture exercises the shipped JavaScript, including
    // aggregate row selection when individual-model percentages are also present.
    func testDashboardFallbackReadsOnlyAggregateRows() throws {
        let context = try XCTUnwrap(JSContext())
        context.evaluateScript("(async function() {" + CursorUsageParser.fetchScript + "})")
        XCTAssertNil(context.exception)
        context.evaluateScript(#"""
        function row(label, percent) {
          const row = {innerText: label + '\n6.5B tokens\n' + percent + '%', parentElement: null};
          const cell = {textContent: label, parentElement: row};
          return {row, cell};
        }
        const cursor = row('Cursor Models', 2.2);
        const other = row('Other Models', 0.0);
        const model = row('grok-4.7-high-fast', 88);
        const section = {
          innerText: 'Included Usage\nOct 3, 2026 - Nov 3, 2026\n' + cursor.row.innerText + '\n' + model.row.innerText + '\n' + other.row.innerText,
          querySelectorAll: () => [cursor.cell, model.cell, other.cell]
        };
        cursor.row.parentElement = other.row.parentElement = model.row.parentElement = section;
        const heading = {textContent: 'Included Usage', innerText: 'Included Usage', parentElement: section};
        var document = {body: {innerText: section.innerText}, querySelectorAll: () => [heading]};
        """#)
        let json = try XCTUnwrap(context.evaluateScript(CursorUsageParser.dashboardScript)?.toString())
        XCTAssertNil(context.exception)
        let result = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        XCTAssertEqual(result["hasUsage"] as? Bool, true)
        let cursor = try XCTUnwrap(result["fiveHour"] as? [String: Any])
        let other = try XCTUnwrap(result["weekly"] as? [String: Any])
        XCTAssertEqual(cursor["precisePercent"] as? Double, 2.2)
        XCTAssertEqual(other["precisePercent"] as? Double, 0)
        XCTAssertNotNil(ISO8601DateFormatter().date(from: (cursor["resetText"] as? String ?? "").replacingOccurrences(of: ".000Z", with: "Z")))

        context.evaluateScript("section.querySelectorAll = () => [cursor.cell, model.cell];")
        let missing = try XCTUnwrap(context.evaluateScript(CursorUsageParser.dashboardScript)?.toString())
        let unavailable = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(missing.utf8)) as? [String: Any])
        XCTAssertEqual(unavailable["hasUsage"] as? Bool, false)
    }
}
