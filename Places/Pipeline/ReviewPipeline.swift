import Foundation
import AVFoundation
import Speech
import FoundationModels
import NaturalLanguage

@Generable
struct GeneratedSegmentation {
    @Guide(description: "The transcript split into consecutive statements, each copied word for word.")
    var statements: [String]
}

@Generable
struct GeneratedFixedStatement {
    @Guide(description: "The corrected statement only, with no explanation or quotation marks")
    var statement: String
}

enum ReviewPipelineError: Error {
    case emptyTranscript
    case speechUnavailable
}

enum ReviewPipeline {

    // MARK: Speech to text

    static func transcribe(fileAt url: URL) async throws -> String {
        guard SpeechTranscriber.isAvailable else {
            throw ReviewPipelineError.speechUnavailable
        }
        
        let transcriber = SpeechTranscriber(
            locale: Locale(identifier: "en-US"),
            transcriptionOptions: [],
            reportingOptions: [],
            attributeOptions: []
        )

        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let file = try AVAudioFile(forReading: url)

        async let collected: String = {
            var text = ""
            for try await result in transcriber.results {
                text += String(result.text.characters)
            }
            return text
        }()

        if let lastSample = try await analyzer.analyzeSequence(from: file) {
            try await analyzer.finalizeAndFinish(through: lastSample)
        } else {
            await analyzer.cancelAndFinishNow()
        }
        return try await collected
    }

    // MARK: Natural breakpoints

    static func segment(transcript: String) async throws -> [String] {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ReviewPipelineError.emptyTranscript }

        var pieces: [String]?

        if case .available = SystemLanguageModel.default.availability {
            let session = LanguageModelSession(instructions: """
                You split a spoken transcript into statements at natural breaks. \
                Each statement is one complete thought. Copy the words exactly as \
                given, in the same order. Do not add, remove, reword or correct anything.
                """)
            if let response = try? await session.respond(to: trimmed, generating: GeneratedSegmentation.self),
               isFaithful(response.content.statements, to: trimmed) {
                pieces = response.content.statements
            }
        }

        if (pieces?.count == wordCount(trimmed)) {
            pieces = sentenceSplit(trimmed)
        }

        return (pieces ?? sentenceSplit(trimmed))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
    
    // MARK: Split Further and Fix Statement

    /// Every statement produced by "Split Further" needs at least this many words.
    static let minWordsPerStatement = 3

    /// Whether a statement is long enough to hold two statements of the minimum size.
    static func canSplit(_ text: String) -> Bool {
        wordCount(text) >= 2 * minWordsPerStatement
    }

    /// Splits one statement into separate ideas. Returns it unchanged if there's no good split.
    static func splitStatement(_ text: String) async -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSplit(trimmed),
              case .available = SystemLanguageModel.default.availability else {
            return [trimmed]
        }

        let session = LanguageModelSession(instructions: """
            You are given one statement from a spoken restaurant review. It may contain more \
            than one idea run together, for example two opinions with no punctuation between \
            them. Split it into separate statements at the natural breaks, one idea each. Each \
            statement must make sense on its own. Copy the words exactly as given, in the same \
            order. Do not add, remove, reword or correct anything. If it is really only one \
            idea, return it unchanged as a single statement.
            """)

        guard let response = try? await session.respond(
            to: trimmed,
            generating: GeneratedSegmentation.self,
            options: GenerationOptions(temperature: 0.1)
        ) else {
            return [trimmed]
        }

        let pieces = response.content.statements
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        // Reject the split if words changed or any piece is a fragment.
        guard pieces.count > 1,
              isFaithful(pieces, to: trimmed),
              pieces.allSatisfy({ wordCount($0) >= minWordsPerStatement }) else {
            return [trimmed]
        }
        return pieces
    }

    /// Rewrites a garbled statement as one coherent thought.
    /// Returns nil if the result is unusable or the statement already reads fine.
    static func fixStatement(_ text: String) async throws -> String? {
        guard case .available = SystemLanguageModel.default.availability else {
            throw AnalysisError.modelUnavailable
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let session = LanguageModelSession(instructions: """
            You clean up one statement from a spoken restaurant review that was typed out by \
            speech recognition. Assume it is meant to be a single coherent thought, even if it \
            reads as garbled or as two fragments joined together. Replace words that were \
            probably misheard with the words the speaker most likely said, and fix the grammar \
            so it reads naturally as one clear statement, and any stuttering or breaks in the flow\
            Keep the speaker's meaning and their own wording wherever it already makes sense. \
            Do not add new facts, opinions, dishes or details.
            """)

        let response = try await session.respond(
            to: "Here is one statement from an English restaurant review: \"\(trimmed)\"",
            generating: GeneratedFixedStatement.self,
            options: GenerationOptions(temperature: 0.2)
        )

        let fixed = response.content.statement
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"“”")))

        // Unusable: empty, or wildly longer than what we gave it.
        guard !fixed.isEmpty, wordCount(fixed) <= wordCount(trimmed) * 2 + 3 else { return nil }
        // Already fine: nothing meaningful changed.
        guard normalized(fixed) != normalized(trimmed) else { return nil }
        return fixed
    }
    
    private static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: \.isWhitespace).count
    }

    private static func isFaithful(_ pieces: [String], to transcript: String) -> Bool {
        !pieces.isEmpty && normalized(pieces.joined()) == normalized(transcript)
    }

    private static func normalized(_ text: String) -> String {
        text.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    private static func sentenceSplit(_ text: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        var result: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            result.append(String(text[range]))
            return true
        }
        return result
    }
}
