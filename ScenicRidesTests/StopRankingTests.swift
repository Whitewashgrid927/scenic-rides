import XCTest
@testable import ScenicRides

@MainActor
final class StopRankingTests: XCTestCase {
    private var request: RideRequest {
        RideRequest(startingPlace: StartingPlace(name: "Private starting point", detail: "Private address", coordinate: StartingPlace.austin.coordinate),
                    duration: .sixty, scenery: [.greenery, .city], options: RideOptions(pace: .stop, stopKind: .coffee, stopDuration: .twenty))
    }
    private var loop: AustinLoop { AustinLoop.allCases.first { $0.id == 13 }! }

    func testValidModelRankingIsAppliedAndPromptExcludesStartingLocation() async throws {
        let request = request; let candidates = Array(loop.stopPlacements(for: request).prefix(4))
        XCTAssertGreaterThan(candidates.count, 1)
        let ids = candidates.reversed().map { $0.stop.id }
        let generator = StubGenerator(ids: ids)
        let ranked = try await OnDeviceStopRanker(generator: generator).rank(candidates, request: request, loop: loop)
        XCTAssertEqual(ranked.method, .onDeviceAI)
        XCTAssertEqual(ranked.placements.map { $0.stop.id }, ids)
        XCTAssertEqual(generator.prompts.count, 1)
        let prompt = try XCTUnwrap(generator.prompts.first)
        XCTAssertFalse(prompt.contains(request.startingPlace.name)); XCTAssertFalse(prompt.contains(request.startingPlace.detail))
        XCTAssertFalse(prompt.contains(String(request.startingPlace.latitude)))
        XCTAssertTrue(prompt.contains("20")); XCTAssertTrue(prompt.contains("Coffee"))
    }

    func testUnknownDuplicateMissingAndEmptyModelIDsFallBackToVerifiedChoices() async throws {
        let request = request; let candidates = Array(loop.stopPlacements(for: request).prefix(4))
        let original = candidates.map { $0.stop.id }
        for ids in [["invented-place"], Array(repeating: original[0], count: original.count), Array(original.dropLast()), []] {
            let result = try await OnDeviceStopRanker(generator: StubGenerator(ids: ids)).rank(candidates, request: request, loop: loop)
            XCTAssertEqual(result.method, .nearby(.invalidOutput))
            XCTAssertEqual(result.placements.map { $0.stop.id }, original)
        }
    }

    func testUnavailableModelNeverStartsInferenceAndReportsTheReason() async throws {
        let pairs: [(LocalAIAvailability, StopSelectionMethod.FallbackReason)] = [(.notEligible, .notEligible), (.disabled, .disabled), (.notReady, .notReady), (.unavailable, .unavailable)]
        for (availability, reason) in pairs {
            let generator = StubGenerator(ids: [], availability: availability)
            let result = try await OnDeviceStopRanker(generator: generator).rank(loop.stopPlacements(for: request), request: request, loop: loop)
            XCTAssertEqual(result.method, .nearby(reason)); XCTAssertTrue(generator.prompts.isEmpty)
        }
    }

    func testGenerationFailureAndTimeoutUseTheNearbyFallback() async throws {
        let candidates = loop.stopPlacements(for: request)
        let failed = StubGenerator(ids: []); failed.fail = true
        let failure = try await OnDeviceStopRanker(generator: failed).rank(candidates, request: request, loop: loop)
        XCTAssertEqual(failure.method, .nearby(.generationFailed))
        let slow = StubGenerator(ids: []); slow.delay = .seconds(60)
        let timeout = try await OnDeviceStopRanker(generator: slow, timeout: .milliseconds(20)).rank(candidates, request: request, loop: loop)
        XCTAssertEqual(timeout.method, .nearby(.timedOut))
    }

    func testCancellationDoesNotReturnAnAIFallbackAsASuccess() async throws {
        let generator = StubGenerator(ids: []); generator.delay = .seconds(60)
        let ranker = OnDeviceStopRanker(generator: generator)
        let task = Task { try await ranker.rank(loop.stopPlacements(for: request), request: request, loop: loop) }
        await generator.waitForStart()
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancellation must propagate.") }
        catch { XCTAssertTrue(error is CancellationError) }
    }
}

@MainActor
private final class StubGenerator: StopRankingGenerating {
    let availability: LocalAIAvailability
    let ids: [String]
    var prompts: [String] = []
    var delay: Duration?
    var fail = false
    private var observer: CheckedContinuation<Void, Never>?
    init(ids: [String], availability: LocalAIAvailability = .available) { self.ids = ids; self.availability = availability }
    func rankedIDs(prompt: String) async throws -> [String] {
        prompts.append(prompt); observer?.resume(); observer = nil
        if let delay { try await Task.sleep(for: delay) }
        if fail { throw Failure.generation }
        return ids
    }
    func waitForStart() async {
        if !prompts.isEmpty { return }
        await withCheckedContinuation { observer = $0 }
    }
    private enum Failure: Error { case generation }
}
