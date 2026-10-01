//
//  ImportFromTextView.swift
//  Places
//
//  Created by Raymond Yang on 9/30/26.
//


import SwiftUI

struct ImportFromTextView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: 44))
                    .foregroundStyle(.secondary)

                Text("Copy the whole message you received, then tap Paste.")
                    .multilineTextAlignment(.center)

                PasteButton(payloadType: String.self) { strings in
                    handle(strings.first ?? "")
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }
            }
            .padding()
            .navigationTitle("Import Text from Clipboard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func handle(_ text: String) {
        do {
            let file = try ReviewPayload.decode(from: text)
            dismiss()
            // Wait for this sheet to close before showing the import screen.
            Task {
                try? await Task.sleep(for: .milliseconds(400))
                ImportCenter.shared.pending = PendingImport(file: file)
            }
        } catch {
            errorMessage = "That doesn't look like a Places review. Copy the whole message, including the long block of letters, and try again."
        }
    }
}