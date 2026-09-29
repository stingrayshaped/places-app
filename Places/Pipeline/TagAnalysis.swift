//
//  TagAnalysis.swift
//  Places
//
//  Created by Raymond Yang on 9/28/26.
//

import Foundation
import FoundationModels

/// A plain copy of a vocabulary entry, safe to hand to the analysis code.
struct TagSnapshot {
    let key: String
    let name: String
    let kind: TagKind
    let section: String
    let definition: String
    let aliases: [String]
}

struct AppliedResult {
    let key: String
    let section: String
    let evidence: [UUID]
}

struct TagAnalysisOutput {
    let results: [AppliedResult]
    /// Sections the model couldn't check this time (existing AI tags there are kept).
    let uncheckedSections: Set<String>
}

@Generable
struct GeneratedMatch {
    @Guide(description: "The exact name of a tag from the list")
    var tag: String

    @Guide(description: "Numbers of the statements that directly say this")
    var lines: [Int]
}

@Generable
struct GeneratedMatches {
    @Guide(description: "Only the tags that apply. Empty if none do.")
    var matches: [GeneratedMatch]
}

@Generable
struct GeneratedVerdict {
    @Guide(description: "yes only if the statement directly says this, otherwise no", .anyOf(["yes", "no"]))
    var answer: String
}

enum TagAnalysis {
    /// Tags per model call. Lower is safer for the on-device model; higher is faster.
    static let maxTagsPerPass = 30

    static func apply(statements: [ReviewStatement],
                      vocabulary: [TagSnapshot]) async throws -> TagAnalysisOutput {
        guard case .available = SystemLanguageModel.default.availability else {
            throw AnalysisError.modelUnavailable
        }
        guard !statements.isEmpty, !vocabulary.isEmpty else {
            return TagAnalysisOutput(results: [], uncheckedSections: [])
        }

        let lines = statements.map(\.text)
        var found: [String: (section: String, lines: [Int])] = [:]
        var unchecked = Set<String>()

        for pass in chunk(vocabulary) {
            do {
                for candidate in try await match(pass: pass, lines: lines) {
                    let confirmed = try await verify(candidate.tag,
                                                     lineNumbers: candidate.lines,
                                                     allLines: lines)
                    if !confirmed.isEmpty {
                        found[candidate.tag.key] = (section: candidate.tag.section, lines: confirmed)
                    }
                }
            } catch LanguageModelSession.GenerationError.unsupportedLanguageOrLocale {
                // The model couldn't read this batch as English. Skip it, keep what we had.
                print("Skipped tag pass (unsupported language):", pass.map(\.section))
                unchecked.formUnion(pass.map(\.section))
            } catch {
                print("Tag pass failed:", error)
                let section = pass.first?.section ?? "?"
                throw AnalysisError.taggingFailed(
                    "pass starting at \(section): \(String(describing: error))"
                )
            }
        }

        // Keep the vocabulary's order so results are stable.
        let results = vocabulary.compactMap { tag -> AppliedResult? in
            guard let hit = found[tag.key] else { return nil }
            return AppliedResult(
                key: tag.key,
                section: tag.section,
                evidence: hit.lines.sorted().map { statements[$0 - 1].id }
            )
        }
        return TagAnalysisOutput(results: results, uncheckedSections: unchecked)
    }

    // MARK: Pass: propose matches

    private static func match(pass: [TagSnapshot],
                              lines: [String]) async throws -> [(tag: TagSnapshot, lines: [Int])] {
        let session = LanguageModelSession(instructions: """
            You match a restaurant reviewer's numbered statements against a fixed list of tags. \
            The review is written in English. \
            Apply a tag only when a statement directly and explicitly says it. Never infer or guess. \
            If a statement says the opposite, or you are not sure, do not apply the tag. \
            Use the exact tag name from the list, and give the numbers of the statements that say it. \
            If no tag applies, return an empty list.
            """)

        let prompt = """
            Below is a list of tags for describing restaurants, each with a short English \
            description of what it means. After it are the numbered statements from a restaurant \
            review, written in English. Decide which tags from the list the statements directly say.

            Tags:
            \(vocabularyText(pass))

            Statements:
            \(numbered(lines))
            """

        let response = try await session.respond(
            to: prompt,
            generating: GeneratedMatches.self,
            options: GenerationOptions(temperature: 0.1)
        )

        return response.content.matches.compactMap { match -> (tag: TagSnapshot, lines: [Int])? in
            guard let tag = lookup(match.tag, in: pass) else { return nil }
            let valid = Set(match.lines.filter { (1...lines.count).contains($0) })
                .sorted()
                .prefix(3)
            return valid.isEmpty ? nil : (tag: tag, lines: Array(valid))
        }
    }

    // MARK: Pass: double-check each match

    private static func verify(_ tag: TagSnapshot,
                               lineNumbers: [Int],
                               allLines: [String]) async throws -> [Int] {
        let claim = "\(tag.name) (\(meaning(of: tag)))"
        var confirmed: [Int] = []

        for number in lineNumbers {
            let session = LanguageModelSession(instructions: """
                You check whether one statement from an English restaurant review directly says \
                something. Answer yes only if the statement clearly says it. Answer no if it says \
                the opposite, is about something else, or you would have to guess.
                """)

            let prompt = """
                Here is one statement from a restaurant review, written in English: \
                "\(allLines[number - 1])"

                Does this statement directly say the following about the restaurant? \
                \(claim)

                Answer yes only if the statement clearly says it.
                """

            do {
                let response = try await session.respond(
                    to: prompt,
                    generating: GeneratedVerdict.self,
                    options: GenerationOptions(temperature: 0.1)
                )
                if response.content.answer == "yes" {
                    confirmed.append(number)
                }
            } catch LanguageModelSession.GenerationError.unsupportedLanguageOrLocale {
                continue   // can't check this one, so treat it as not confirmed
            }
        }
        return confirmed
    }

    // MARK: Helpers

    /// The tag's definition, or a written-out meaning when it has none (cuisines, types).
    private static func meaning(of tag: TagSnapshot) -> String {
        tag.definition.isEmpty
            ? "the reviewer says the place or its food is \(tag.name)"
            : tag.definition
    }

    /// Groups whole sections into batches of at most `maxTagsPerPass` tags.
    private static func chunk(_ vocabulary: [TagSnapshot]) -> [[TagSnapshot]] {
        var order: [String] = []
        var buckets: [String: [TagSnapshot]] = [:]
        for tag in vocabulary {
            if buckets[tag.section] == nil { order.append(tag.section) }
            buckets[tag.section, default: []].append(tag)
        }

        var passes: [[TagSnapshot]] = []
        var current: [TagSnapshot] = []
        for section in order {
            let group = buckets[section] ?? []
            if !current.isEmpty && current.count + group.count > maxTagsPerPass {
                passes.append(current)
                current = []
            }
            current += group
        }
        if !current.isEmpty { passes.append(current) }
        return passes
    }

    private static func vocabularyText(_ pass: [TagSnapshot]) -> String {
        var output: [String] = []
        var currentSection = ""
        for tag in pass {
            if tag.section != currentSection {
                currentSection = tag.section
                output.append("\(currentSection):")
            }
            var line = "- \(tag.name): \(meaning(of: tag))"
            if !tag.aliases.isEmpty { line += " (also: \(tag.aliases.joined(separator: ", ")))" }
            output.append(line)
        }
        return output.joined(separator: "\n")
    }

    private static func lookup(_ name: String, in pass: [TagSnapshot]) -> TagSnapshot? {
        let wanted = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return pass.first { $0.name.caseInsensitiveCompare(wanted) == .orderedSame }
            ?? pass.first { tag in
                tag.aliases.contains { $0.caseInsensitiveCompare(wanted) == .orderedSame }
            }
    }

    private static func numbered(_ lines: [String]) -> String {
        lines.enumerated()
            .map { "\($0.offset + 1). \($0.element)" }
            .joined(separator: "\n")
    }
}
