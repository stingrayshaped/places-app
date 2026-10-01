import Foundation
import FoundationModels
import Observation
import SwiftData

enum AnalysisError: Error {
    case modelUnavailable
    case taggingFailed(String)
}

// MARK: - Summary pass

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

    /// Regenerates the summary and the AI-applied tags. Skips the work if
    /// nothing changed, unless `force` is true.
    func refresh(_ restaurant: Restaurant, force: Bool = false) async {
        guard restaurant.isMine else { return }   // received reviews are never re-analyzed
        let id = restaurant.id
        guard !running.contains(id) else { return }
        guard force || restaurant.summaryIsStale else { return }

        running.insert(id)
        errors[id] = nil
        defer { running.remove(id) }

        let statements = restaurant.statements
        let lines = statements.map(\.text)
        let source = restaurant.statementsSource

        // Nothing left to analyze: clear everything the AI produced.
        if statements.isEmpty {
            restaurant.summary = ""
            restaurant.analyzedSource = ""
            restaurant.appliedTags.removeAll { $0.source == .ai }
            return
        }

        do {
            restaurant.summary = try await ReviewAnalysis.summarize(statements: lines)

            let vocabulary = snapshots(for: restaurant)
            let output = try await TagAnalysis.apply(statements: statements, vocabulary: vocabulary)
            applyResults(output, vocabulary: vocabulary, to: restaurant)

            restaurant.analyzedSource = source
            restaurant.updatedAt = .now

            if !output.uncheckedSections.isEmpty {
                errors[id] = "Couldn't check these tag sections: "
                    + output.uncheckedSections.sorted().joined(separator: ", ") + "."
            }
        } catch AnalysisError.modelUnavailable {
            errors[id] = "Apple Intelligence isn't available on this device."
        } catch AnalysisError.taggingFailed(let detail) {
            print("Tagging failed:", detail)
            errors[id] = "Couldn't apply tags: \(detail)"
        } catch {
            print("Analysis failed:", error)
            errors[id] = "Couldn't analyze the review. Try again."
        }
    }

    // MARK: Helpers

    private func snapshots(for restaurant: Restaurant) -> [TagSnapshot] {
        let descriptor = FetchDescriptor<TagDefinition>(sortBy: [SortDescriptor(\.sortOrder)])
        let definitions = (try? restaurant.modelContext?.fetch(descriptor)) ?? []
        return definitions.map {
            TagSnapshot(key: $0.key, name: $0.name, kind: $0.kind, section: $0.section,
                        definition: $0.definition, aliases: $0.aliases)
        }
    }

    /// Manual tags always stay. AI tags are recomputed, skipping anything
    /// the user removed or already chose by hand.
    private func applyResults(_ output: TagAnalysisOutput,
                              vocabulary: [TagSnapshot],
                              to restaurant: Restaurant) {
        let sectionByKey = Dictionary(vocabulary.map { ($0.key, $0.section) },
                                      uniquingKeysWith: { first, _ in first })
        let manual = restaurant.appliedTags.filter { $0.source == .manual }
        let manualKeys = Set(manual.map(\.tagKey))
        let manualSections = Set(manual.compactMap { sectionByKey[$0.tagKey] })
        let rejected = Set(restaurant.rejectedTagKeys)

        // AI tags in sections we couldn't check stay exactly as they were.
        let keptAI = restaurant.appliedTags.filter { application in
            application.source == .ai
            && output.uncheckedSections.contains(sectionByKey[application.tagKey] ?? "")
        }
        let keptKeys = Set(keptAI.map(\.tagKey))

        var eligible = output.results.filter {
            !manualKeys.contains($0.key)
            && !rejected.contains($0.key)
            && !keptKeys.contains($0.key)
        }

        // Single-choice sections (like Price): skip if the user already chose,
        // and drop the section if the AI found more than one.
        for section in TagRules.singleChoiceSections {
            let count = eligible.filter { $0.section == section }.count
            if manualSections.contains(section) || count > 1 {
                eligible.removeAll { $0.section == section }
            }
        }

        restaurant.appliedTags = manual + keptAI + eligible.map {
            TagApplication(tagKey: $0.key, source: .ai, evidence: $0.evidence)
        }
    }
}
