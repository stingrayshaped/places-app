import SwiftUI
import SwiftData

struct ImportPreviewView: View {
    let file: ReviewFile

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var restaurants: [Restaurant]

    @State private var replaceNewer = false
    @State private var adoptProfile = false
    @State private var errorMessage: String?

    private var existingByID: [UUID: Restaurant] {
        Dictionary(restaurants.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private func status(_ record: RestaurantRecord) -> ImportStatus {
        ReviewImporter.status(of: record, existing: existingByID[record.id])
    }

    private var hasNewerHere: Bool {
        file.restaurants.contains { status($0) == .newerHere }
    }

    private var foreignProfile: ProfileRecord? {
        guard let profile = file.profile,
              profile.authorID != MyProfile.shared.authorID else { return nil }
        return profile
    }

    /// How many reviews the Import button would add or update.
    private var actionableCount: Int {
        file.restaurants.filter {
            switch status($0) {
            case .new, .update: true
            case .newerHere: replaceNewer
            case .upToDate: false
            }
        }.count
    }

    var body: some View {
        NavigationStack {
            List {
                Section(file.restaurants.count == 1 ? "1 review" : "\(file.restaurants.count) reviews") {
                    ForEach(file.restaurants) { record in
                        row(for: record)
                    }
                }

                if foreignProfile != nil || hasNewerHere {
                    Section {
                        if let profile = foreignProfile {
                            Toggle("This is my backup", isOn: $adoptProfile)
                                .accessibilityHint("Restores the name \(profile.name) and your identity")
                        }
                        if hasNewerHere {
                            Toggle("Replace newer copies too", isOn: $replaceNewer)
                        }
                    } footer: {
                        Text("Turn on “This is my backup” when restoring on a new phone, so your reviews are recognized as yours. “Replace newer copies too” overwrites reviews you have with older versions from this file.")
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Import")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import", action: runImport)
                        .disabled(actionableCount == 0)
                }
            }
        }
    }

    private func row(for record: RestaurantRecord) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(record.name)
                .font(.headline)
            if !record.address.isEmpty {
                Text(record.address)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                Text("From \(authorLabel(record))")
                Text("·")
                Text("\(record.statements.count) statements")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Text(statusText(status(record)))
                .font(.caption.weight(.semibold))
                .foregroundStyle(statusColor(status(record)))
        }
    }

    private func authorLabel(_ record: RestaurantRecord) -> String {
        if ReviewImporter.incomingIsMine(record) { return "you" }
        let name = record.authorName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? "an unknown author" : name
    }

    private func statusText(_ status: ImportStatus) -> String {
        switch status {
        case .new: "New"
        case .update: "Update available"
        case .upToDate: "Already up to date"
        case .newerHere: "You have a newer version"
        }
    }

    private func statusColor(_ status: ImportStatus) -> Color {
        switch status {
        case .new: .green
        case .update: .blue
        case .upToDate: .secondary
        case .newerHere: .orange
        }
    }

    private func runImport() {
        do {
            try ReviewImporter.importFile(file,
                                          replaceNewer: replaceNewer,
                                          adoptProfile: adoptProfile,
                                          into: modelContext)
            dismiss()
        } catch {
            errorMessage = "Couldn't import: \(error.localizedDescription)"
        }
    }
}
