import Foundation
import FoundationModels

enum LocalAIAvailability: Equatable { case available, notEligible, disabled, notReady, unavailable }

enum StopSelectionMethod: Equatable {
    case onDeviceAI
    case nearby(FallbackReason)

    enum FallbackReason: Equatable { case notEligible, disabled, notReady, unavailable, generationFailed, invalidOutput, timedOut }
    var title: String {
        switch self {
        case .onDeviceAI: "Picked with on-device AI"
        case .nearby: "Nearby match · AI unavailable"
        }
    }
    var detail: String {
        switch self {
        case .onDeviceAI:
            "Apple’s on-device model ranked nearby catalog stops using your scenery choices and planned stop time. MapKit calculated the driving route and total estimate."
        case let .nearby(reason):
            switch reason {
            case .notEligible: "This device does not support the local model. Your stop was selected by proximity and scenery."
            case .disabled: "Apple Intelligence is turned off. Your stop was selected by proximity and scenery."
            case .notReady: "The local model is not ready. Your stop was selected by proximity and scenery."
            case .unavailable: "Local AI is unavailable. Your stop was selected by proximity and scenery."
            case .generationFailed: "Local AI could not complete this suggestion. Your stop was selected by proximity and scenery."
            case .invalidOutput: "The AI suggestion could not be verified against the nearby choices. Your stop was selected by proximity and scenery."
            case .timedOut: "Local AI took too long. Your stop was selected by proximity and scenery."
            }
        }
    }
}

struct RankedStops {
    let placements: [StopPlacement]
    let method: StopSelectionMethod
}

@MainActor
protocol StopRanking {
    func rank(_ candidates: [StopPlacement], request: RideRequest, loop: AustinLoop) async throws -> RankedStops
}

@MainActor
protocol StopRankingGenerating: Sendable {
    var availability: LocalAIAvailability { get }
    func rankedIDs(prompt: String) async throws -> [String]
}

@Generable
private struct GeneratedStopRanking {
    @Guide(description: "Every candidate stop ID, exactly once, best match first. Copy only IDs supplied in the prompt.", .minimumCount(1), .maximumCount(4))
    var stopIDs: [String]
}

@MainActor
final class AppleStopRankingGenerator: StopRankingGenerating {
    // SystemLanguageModel is Apple's on-device model. No cloud model or provider is used.
    private let model = SystemLanguageModel.default
    var availability: LocalAIAvailability {
        switch model.availability {
        case .available: .available
        case let .unavailable(reason):
            switch reason {
            case .deviceNotEligible: .notEligible
            case .appleIntelligenceNotEnabled: .disabled
            case .modelNotReady: .notReady
            @unknown default: .unavailable
            }
        }
    }

    func rankedIDs(prompt: String) async throws -> [String] {
        let session = LanguageModelSession(model: model, instructions: """
        Rank the supplied public stops for a scenic round trip. Use only the supplied candidate facts.
        Prefer scenery matching the rider's choices and a small geographic detour.
        Consider the planned stop time and access notes. Do not invent places, opening hours,
        road conditions, or travel times. The app separately checks driving time with MapKit.
        Return every supplied stop ID exactly once in preference order. Do not add any other IDs.
        """)
        let response = try await session.respond(to: prompt, generating: GeneratedStopRanking.self,
                                                 options: GenerationOptions(temperature: 0, maximumResponseTokens: 160))
        return response.content.stopIDs
    }
}

@MainActor
final class OnDeviceStopRanker: StopRanking {
    private let generator: any StopRankingGenerating
    private let timeout: Duration
    init(generator: any StopRankingGenerating = AppleStopRankingGenerator(), timeout: Duration = .seconds(8)) {
        self.generator = generator; self.timeout = timeout
    }

    func rank(_ candidates: [StopPlacement], request: RideRequest, loop: AustinLoop) async throws -> RankedStops {
        try Task.checkCancellation()
        let shortlist = Array(candidates.prefix(4))
        func fallback(_ reason: StopSelectionMethod.FallbackReason) -> RankedStops {
            RankedStops(placements: shortlist, method: .nearby(reason))
        }
        switch generator.availability {
        case .notEligible: return fallback(.notEligible)
        case .disabled: return fallback(.disabled)
        case .notReady: return fallback(.notReady)
        case .unavailable: return fallback(.unavailable)
        case .available: break
        }
        guard !shortlist.isEmpty else { return fallback(.unavailable) }
        do {
            let prompt = try Self.prompt(for: shortlist, request: request, loop: loop)
            let generator = self.generator; let timeout = self.timeout
            let ids = try await withThrowingTaskGroup(of: [String].self) { group in
                group.addTask { [generator, prompt] in try await generator.rankedIDs(prompt: prompt) }
                group.addTask {
                    try await Task.sleep(for: timeout)
                    throw RankingError.timedOut
                }
                defer { group.cancelAll() }
                return try await group.next() ?? []
            }
            try Task.checkCancellation()
            let allowed = Set(shortlist.map { $0.stop.id })
            guard ids.count == shortlist.count, Set(ids).count == ids.count, Set(ids) == allowed else {
                return fallback(.invalidOutput)
            }
            let ranked = ids.compactMap { id in shortlist.first { $0.stop.id == id } }
            return RankedStops(placements: ranked, method: .onDeviceAI)
        } catch {
            try Task.checkCancellation()
            return fallback(error is RankingError ? .timedOut : .generationFailed)
        }
    }

    /// Only typed preferences and public catalog facts enter the prompt. No start address,
    /// user location, device identifiers, or location history is included or logged.
    static func prompt(for candidates: [StopPlacement], request: RideRequest, loop: AustinLoop) throws -> String {
        struct Candidate: Encodable {
            let id: String; let name: String; let scenery: String; let accessNote: String; let approximateExtraMeters: Int
        }
        struct Input: Encodable {
            let route: String; let area: String; let scenery: String; let stopType: String
            let stopMinutes: Int; let totalBudgetMinutes: Int; let candidates: [Candidate]
        }
        let input = Input(route: loop.name, area: loop.area, scenery: request.sceneryLabel,
                          stopType: request.options.stopKind.name, stopMinutes: request.options.stopMinutes,
                          totalBudgetMinutes: request.duration.rawValue,
                          candidates: candidates.map { Candidate(id: $0.stop.id, name: $0.stop.name,
                              scenery: Scenery.label(for: $0.stop.scenery), accessNote: $0.stop.note,
                              approximateExtraMeters: Int(($0.addedDistance / 100).rounded()) * 100) })
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(input), as: UTF8.self)
    }
    private enum RankingError: Error { case timedOut }
}
