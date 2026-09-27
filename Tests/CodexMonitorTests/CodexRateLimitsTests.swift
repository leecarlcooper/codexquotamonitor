import XCTest
@testable import CodexMonitor

final class CodexRateLimitsTests: XCTestCase {
    private func decode(_ json: String) throws -> CodexRateLimitsClient.Response {
        try JSONDecoder().decode(CodexRateLimitsClient.Response.self, from: Data(json.utf8))
    }

    func testUsedPercentAndAbsoluteReset() throws {
        let result = try decode("""
        {"rateLimits":{"limitId":"codex","primary":{"usedPercent":45,"windowDurationMins":300,"resetsAt":2000000000},"secondary":{"usedPercent":7,"windowDurationMins":10080,"resetsAt":2000600000}}}
        """)
        XCTAssertEqual(result.limits?.fiveHour?.percentRemaining, 55)
        XCTAssertEqual(result.limits?.weekly?.percentRemaining, 93)
        let reset = try XCTUnwrap(result.limits?.fiveHour?.resetText)
        XCTAssertEqual(ISO8601DateFormatter().date(from: reset)?.timeIntervalSince1970, 2000000000)
        XCTAssertEqual(ResetCountdownFormatter.countdown(from: reset, now: Date(timeIntervalSince1970: 1999996400)), "1h 0m")
    }

    func testSelectsCodexBucketAndUsesDurationRatherThanPosition() throws {
        let result = try decode("""
        {"rateLimits":{"limitId":"other","primary":{"usedPercent":99,"windowDurationMins":300}},"rateLimitsByLimitId":{"codex":{"primary":{"usedPercent":20,"windowDurationMins":10080},"secondary":{"usedPercent":10,"windowDurationMins":300}},"other":{"primary":{"usedPercent":99,"windowDurationMins":300}}}}
        """)
        XCTAssertEqual(result.limits?.fiveHour?.percentRemaining, 90)
        XCTAssertEqual(result.limits?.weekly?.percentRemaining, 80)
    }

    func testDoesNotPresentOtherOrUnknownWindowsAsCodex() throws {
        for json in [
             #"{"rateLimits":{"limitId":"other","primary":{"usedPercent":10,"windowDurationMins":300}}}"#,
             #"{"rateLimits":{"primary":{"usedPercent":10,"windowDurationMins":15}}}"#,
             #"{"rateLimitsByLimitId":{"other":{"primary":{"usedPercent":10,"windowDurationMins":300}}}}"#,
             #"{"rateLimits":null}"#
        ] {
            XCTAssertNil(try decode(json).limits)
        }
    }

    func testPartialWindowsAndInvalidPercent() throws {
        let result = try decode("""
        {"rateLimits":{"primary":{"usedPercent":101,"windowDurationMins":300},"secondary":{"usedPercent":100,"windowDurationMins":10080}}}
        """)
        XCTAssertNil(result.limits?.fiveHour)
        XCTAssertEqual(result.limits?.weekly?.percentRemaining, 0)
        XCTAssertEqual(result.limits?.weekly?.resetText, "")
    }

    func testCompanionExportIncludesAbsoluteReset() throws {
        let limit = UsageLimit(percent: 20, metric: .used, resetText: "2033-05-18T03:33:20Z")
        let snapshot = QuotaStatusSnapshot.LimitStatus(limit: limit)
        XCTAssertEqual(snapshot.resetAt, limit.resetText)
        XCTAssertEqual(snapshot.percentRemaining, 80)
        let data = try JSONEncoder().encode(snapshot)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["resetAt"] as? String, limit.resetText)
    }

    func testWidgetPreservesValuesButNotOldSuccessState() {
        let previous = QuotaWidgetSnapshot.placeholder.codex
        let failed = QuotaProductSnapshot(product: .codex, shortTitle: "5 hour limit", weeklyTitle: "Weekly limit",
                                          shortLimit: nil, weeklyLimit: nil, authState: .unknown,
                                          errorMessage: "Request failed", lastUpdated: nil)
        let preserved = failed.preservingLastKnownValues(from: previous)
        XCTAssertEqual(preserved.shortLimit, previous.shortLimit)
        XCTAssertEqual(preserved.lastUpdated, previous.lastUpdated)
        XCTAssertEqual(preserved.errorMessage, "Request failed")
        XCTAssertEqual(preserved.authState, .unknown)
    }

    @MainActor
    func testUnavailableExecutableCompletes() {
        let client = CodexRateLimitsClient()
        var failed = false
        client.fetch(executable: nil) { if case .failure = $0 { failed = true } }
        XCTAssertTrue(failed)
    }

    @MainActor
    func testProtocolHandshakeAndFragmentedResponse() async throws {
        let script = """
        #!/usr/bin/python3
        import sys,json,time
        assert json.loads(sys.stdin.readline())['method']=='initialize'
        print('{"id":1,"result":{}}',flush=True)
        assert json.loads(sys.stdin.readline())['method']=='initialized'
        assert json.loads(sys.stdin.readline())['method']=='account/rateLimits/read'
        sys.stdout.write('{"method":"notice"}\\n{"id":2,');sys.stdout.flush()
        time.sleep(.03)
        print('"result":{"rateLimits":{"primary":{"usedPercent":12,"windowDurationMins":300}}}}',flush=True)
        sys.stdin.read()
        """
        let url = try fixture(script)
        defer { try? FileManager.default.removeItem(at: url) }
        let client = CodexRateLimitsClient()
        let done = expectation(description: "response")
        client.fetch(executable: url) { result in
            XCTAssertEqual(try? result.get().limits?.fiveHour?.percentRemaining, 88)
            done.fulfill()
        }
        await fulfillment(of: [done], timeout: 5)
    }

    @MainActor
    func testTimeoutAndProcessExitCompleteExactlyOnce() async throws {
        for script in ["#!/bin/sh\nexec /bin/sleep 10\n", "#!/bin/sh\nexit 1\n"] {
            let url = try fixture(script)
            defer { try? FileManager.default.removeItem(at: url) }
            let client = CodexRateLimitsClient()
            let done = expectation(description: "failure")
            done.assertForOverFulfill = true
            client.fetch(executable: url, timeout: 0.1) { result in
                if case .success = result { XCTFail("Expected failure") }
                done.fulfill()
            }
            await fulfillment(of: [done], timeout: 3)
        }
    }

    private func fixture(_ script: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        return url
    }
}
