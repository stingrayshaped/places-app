//
//  RecorderError.swift
//  Places
//
//  Created by Raymond Yang on 9/28/26.
//


import AVFoundation
import Observation

enum RecorderError: Error {
    case permissionDenied
}

@Observable
final class AudioRecorder {
    private(set) var isRecording = false
    private(set) var fileName: String?
    private var recorder: AVAudioRecorder?

    static var recordingsDirectory: URL {
        let dir = URL.documentsDirectory.appending(path: "Recordings", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func start() async throws {
        guard await AVAudioApplication.requestRecordPermission() else {
            throw RecorderError.permissionDenied
        }
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default)
        try session.setActive(true)
        #endif

        let name = "\(UUID().uuidString).m4a"
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        let url = Self.recordingsDirectory.appending(path: name)
        recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder?.record()
        fileName = name
        isRecording = true
    }

    func stop() {
        recorder?.stop()
        recorder = nil
        isRecording = false
    }
}
