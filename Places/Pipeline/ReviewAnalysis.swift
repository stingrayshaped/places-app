import Foundation
import FoundationModels
import Observation

enum AnalysisError: Error {
    case modelUnavailable
}

// MARK: - The pass

enum ReviewAnalysis {

    /// Statements → summary
    static func summarize(statements: [String]) async throws -> String {
        guard case .available = SystemLanguageModel.default.availability else {
            throw AnalysisError.modelUnavailable
        }
        let session = LanguageModelSession(instructions: """
            You write a short summary of a restaurant review from the reviewer's \
            numbered statements. Write two to four sentences of plain, natural prose \
            in the reviewer's voice. Use only what the statements say. Do not invent \
            dishes, prices, ratings or opinions. Do not mention the numbering.
            """)
        let response = try await session.respond(
            to: numbered(statements),
            options: GenerationOptions(temperature: 0.3)
        )
        return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func numbered(_ lines: [String]) -> String {
        lines.enumerated()
            .map { "\($0.offset + 1). \($0.element)" }
            .joined(separator: "\n")
    }
}

// MARK: - Coordinator

@MainActor
@Observable
final class AnalysisCenter {
    static let shared = AnalysisCenter()

    private(set) var running: Set<UUID> = []
    private(set) var errors: [UUID: String] = [:]

    func isRunning(_ restaurant: Restaurant) -> Bool {
        running.contains(restaurant.id)
    }

    func error(for restaurant: Restaurant) -> String? {
        errors[restaurant.id]
    }

    /// Regenerates the summary. Skips the work if nothing changed,
    /// unless `force` is true.
    func refresh(_ restaurant: Restaurant, force: Bool = false) async {
        let id = restaurant.id
        guard !running.contains(id) else { return }
        guard force || restaurant.summaryIsStale else { return }

        running.insert(id)
        errors[id] = nil
        defer { running.remove(id) }

        let lines = restaurant.statements.map(\.text)
        let source = restaurant.statementsSource

        // Nothing left to summarize: clear the derived fields.
        if lines.isEmpty {
            restaurant.summary = ""
            restaurant.analyzedSource = ""
            return
        }

        do {
            restaurant.summary = try await ReviewAnalysis.summarize(statements: lines)
            restaurant.analyzedSource = source
            restaurant.updatedAt = .now
        } catch AnalysisError.modelUnavailable {
            errors[id] = "Apple Intelligence isn't available on this device."
        } catch {
            print("Analysis failed:", error)
            errors[id] = "Couldn't generate the summary. Try again."
        }
    }
}
