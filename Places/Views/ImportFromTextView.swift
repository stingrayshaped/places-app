import SwiftUI
import SwiftData

struct ImportFromTextView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var parsed: ParsedReview?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if let parsed {
                    preview(parsed)
                } else {
                    pasteStep
                }
            }
            .navigationTitle("Import Text from Clipboard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        if let parsed { create(parsed) }
                    }
                    .disabled(parsed == nil)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: Step 1: paste

    private var pasteStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)

            Text("Copy the text of a review that someone shared with you, then tap Paste. It becomes a new review of your own.")
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
    }

    // MARK: Step 2: check and create

    private func preview(_ parsed: ParsedReview) -> some View {
        List {
            Section {
                Text(parsed.name)
                    .font(.headline)
                if !parsed.address.isEmpty {
                    Text(parsed.address)
                        .foregroundStyle(.secondary)
                }
            } footer: {
                Text("This is added as a new review of your own. A summary and tags are created for it when Apple Intelligence is available.")
            }

            Section("\(parsed.statements.count) statements") {
                ForEach(Array(parsed.statements.enumerated()), id: \.offset) { index, text in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text("\(index + 1)")
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 28, alignment: .trailing)
                        Text(text)
                    }
                }
            }
        }
    }

    // MARK: Actions

    private func handle(_ text: String) {
        if let result = ReviewTextImport.parse(text) {
            parsed = result
            errorMessage = nil
        } else {
            errorMessage = "Couldn't find a review in that text. It should start with the restaurant's name, followed by numbered statements."
        }
    }

    private func create(_ parsed: ParsedReview) {
        // A brand-new review: new id, and no author means it's yours.
        let restaurant = Restaurant(name: parsed.name, address: parsed.address)
        restaurant.statements = parsed.statements.map { ReviewStatement(text: $0) }
        modelContext.insert(restaurant)
        try? modelContext.save()
        dismiss()

        Task { await AnalysisCenter.shared.refresh(restaurant) }
    }
}
