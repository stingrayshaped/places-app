import Foundation
import AVFoundation
import Speech
import FoundationModels
import NaturalLanguage

@Generable
struct GeneratedSegmentation {
    @Guide(description: "The sentence divided into one or more consecutive statements, each copied word for word. Use a single statement if it is only one idea.")
    var statements: [String]
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

    /// Sentences up to this many words are always kept as one statement.
    static let minWordsPerStatement = 3

    static func segment(transcript: String) async throws -> [String] {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ReviewPipelineError.emptyTranscript }

        var statements: [String] = []
        for sentence in sentenceSplit(trimmed) {
            let cleaned = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
            if cleaned.isEmpty { continue }

            if wordCount(cleaned) >= minWordsPerStatement {
                statements.append(cleaned)
            } else {
                statements += await splitLongSentence(cleaned)
            }
        }
        return statements
    }

    /// Asks the model to split one long sentence. Falls back to keeping it whole.
    private static func splitLongSentence(_ sentence: String) async -> [String] {
        guard case .available = SystemLanguageModel.default.availability else {
            return [sentence]
        }

        let session = LanguageModelSession(instructions: """
            You are given one long sentence from a spoken restaurant review. \
            If it contains several separate ideas, split it into separate statements \
            at the natural breaks. If it is really one idea, return it unchanged as a \
            single statement. Copy the words exactly as given, in the same order. \
            Do not add, remove, reword or correct anything.
            """)

        guard let response = try? await session.respond(
            to: sentence,
            generating: GeneratedSegmentation.self,
            options: GenerationOptions(temperature: 0.1)
        ) else {
            return [sentence]
        }

        let pieces = response.content.statements
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        // Reject the split if words were changed or any piece is a fragment.
        guard isFaithful(pieces, to: sentence),
              pieces.allSatisfy({ wordCount($0) >= 3 }) else {
            return [sentence]
        }
        return pieces
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
