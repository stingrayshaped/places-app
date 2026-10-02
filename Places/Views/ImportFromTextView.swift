import SwiftUI
import SwiftData

struct ImportFromTextView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var parsed: [ParsedReview] = []
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if parsed.isEmpty {
                    pasteStep
                } else {
                    preview
                }
            }
            .navigationTitle("Import Text from Clipboard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create", action: create)
                        .disabled(parsed.isEmpty)
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

    private var preview: some View {
        List {
            ForEach(Array(parsed.enumerated()), id: \.offset) { _, review in
                Section {
                    Text(review.name)
                        .font(.headline)
                    if !review.address.isEmpty {
                        Text(review.address)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(Array(review.statements.enumerated()), id: \.offset) { index, text in
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

            Section {
            } footer: {
                Text("These are added as new reviews of your own, under the reviewer name you used last. A summary and tags are created for each when Apple Intelligence is available.")
            }
        }
    }

    // MARK: Actions

    private func handle(_ text: String) {
        let result = ReviewTextImport.parseAll(text)
        if result.isEmpty {
            errorMessage = "Couldn't find a review in that text. It should start with the restaurant's name, followed by numbered statements."
        } else {
            parsed = result
            errorMessage = nil
        }
    }

    private func create() {
        var created: [Restaurant] = []
        for review in parsed {
            // A brand-new review: new id, and no author id means it's yours.
            let restaurant = Restaurant(name: review.name, address: review.address)
            restaurant.authorName = MyProfile.shared.displayName
            restaurant.statements = review.statements.map { ReviewStatement(text: $0) }
            modelContext.insert(restaurant)
            created.append(restaurant)
        }
        try? modelContext.save()
        dismiss()

        Task {
            for restaurant in created {
                await AnalysisCenter.shared.refresh(restaurant)
            }
        }
    }
}
