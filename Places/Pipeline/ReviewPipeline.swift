import Foundation
import AVFoundation
import Speech
import FoundationModels
import NaturalLanguage

@Generable
struct GeneratedSegmentation {
    @Guide(description: "The transcript split into consecutive statements, each copied word for word")
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

        return (pieces ?? sentenceSplit(trimmed))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
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
