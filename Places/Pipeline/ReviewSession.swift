//
//  ReviewSession.swift
//  Places
//
//  Created by Raymond Yang on 9/28/26.
//


import SwiftUI
import Observation

@MainActor
@Observable
final class ReviewSession {
    enum Stage {
        case idle, recording, transcribing, segmenting
    }

    private(set) var stage: Stage = .idle
    private(set) var errorMessage: String?
    private(set) var pendingFileName: String?   // set only if processing failed

    private let recorder = AudioRecorder()

    var isRecording: Bool { stage == .recording }
    var isBusy: Bool { stage == .transcribing || stage == .segmenting }

    func toggleRecording(for restaurant: Restaurant) async {
        if isRecording {
            recorder.stop()
            guard let fileName = recorder.fileName else {
                stage = .idle
                return
            }
            await process(fileName: fileName, into: restaurant)
        } else {
            await startRecording()
        }
    }

    func retry(for restaurant: Restaurant) async {
        guard let fileName = pendingFileName else { return }
        await process(fileName: fileName, into: restaurant)
    }

    /// Call when the screen closes so a half-finished recording doesn't linger.
    func discardIfRecording() {
        guard isRecording else { return }
        recorder.stop()
        stage = .idle
    }

    private func startRecording() async {
        errorMessage = nil
        pendingFileName = nil
        do {
            try await recorder.start()
            stage = .recording
        } catch {
            errorMessage = "Couldn't start recording. Check microphone permission."
        }
    }

    private func process(fileName: String, into restaurant: Restaurant) async {
        errorMessage = nil
        do {
            stage = .transcribing
            let url = AudioRecorder.recordingsDirectory.appending(path: fileName)
            let transcript = try await ReviewPipeline.transcribe(fileAt: url)
            print("Transcript:", transcript)

            stage = .segmenting
            let pieces = try await ReviewPipeline.segment(transcript: transcript)

            restaurant.statements += pieces.map {
                ReviewStatement(text: $0, sourceAudio: fileName)
            }
            restaurant.updatedAt = .now
            Task { await AnalysisCenter.shared.refresh(restaurant) }
            pendingFileName = nil
        } catch ReviewPipelineError.emptyTranscript {
            errorMessage = "Didn't catch anything. Try recording again."
            pendingFileName = nil
        } catch {
            print("Review processing failed:", error)
            errorMessage = "Couldn't process that recording: \(error.localizedDescription)"
            pendingFileName = fileName
        }
        stage = .idle
    }
}
