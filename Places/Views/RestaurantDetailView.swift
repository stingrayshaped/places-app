import SwiftUI
import SwiftData

struct RestaurantDetailView: View {
    @Bindable var restaurant: Restaurant
    @Query(sort: \TagDefinition.sortOrder) private var definitions: [TagDefinition]

    private var center: AnalysisCenter { .shared }

    var body: some View {
        List {
            Section("Summary") {
                summaryContent
            }

            if !appliedWarnings.isEmpty {
                Section("Warnings") {
                    FlowLayout {
                        ForEach(appliedWarnings) { WarningChip(text: $0.name) }
                    }
                    .padding(.vertical, 4)
                }
            }

            Section("Tags") {
                if !appliedTags.isEmpty {
                    FlowLayout {
                        ForEach(appliedTags) { TagChip(text: $0.name) }
                    }
                    .padding(.vertical, 4)
                }
                NavigationLink {
                    TagPickerView(restaurant: restaurant)
                } label: {
                    Label("Edit Tags & Warnings", systemImage: "tag")
                }
            }

            Section {
                NavigationLink {
                    ReviewEditorView(restaurant: restaurant)
                } label: {
                    HStack {
                        Label("Statements", systemImage: "list.number")
                        Spacer()
                        Text("\(restaurant.statements.count)")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Details") {
                TextField("Restaurant Name", text: $restaurant.name)
                TextField("Address", text: $restaurant.address)
            }
        }
        .navigationTitle(restaurant.name)
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { restaurant.updatedAt = .now }
    }

    // MARK: Applied tags and warnings

    private var appliedTags: [TagDefinition] { applied(.tag) }
    private var appliedWarnings: [TagDefinition] { applied(.warning) }

    private func applied(_ kind: TagKind) -> [TagDefinition] {
        let keys = Set(restaurant.appliedTags.map(\.tagKey))
        return definitions.filter { $0.kind == kind && keys.contains($0.key) }
    }

    // MARK: Summary

    @ViewBuilder
    private var summaryContent: some View {
        if center.isRunning(restaurant) {
            HStack {
                ProgressView()
                Text("Writing summary…")
                    .foregroundStyle(.secondary)
            }
        } else if restaurant.statements.isEmpty {
            Text("Record a review to see a summary here.")
                .foregroundStyle(.secondary)
        } else {
            if restaurant.summary.isEmpty {
                Text("No summary yet.")
                    .foregroundStyle(.secondary)
            } else {
                Text(restaurant.summary)
            }

            if restaurant.summaryIsStale && !restaurant.summary.isEmpty {
                Text("Statements changed since this summary was written.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let message = center.error(for: restaurant) {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            Button {
                Task { await center.refresh(restaurant, force: true) }
            } label: {
                Label(buttonTitle, systemImage: "sparkles")
            }
        }
    }

    private var buttonTitle: String {
        if restaurant.summary.isEmpty { return "Generate Summary" }
        return restaurant.summaryIsStale ? "Update Summary" : "Regenerate"
    }
}

struct TagChip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.subheadline)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.accentColor.opacity(0.15), in: Capsule())
    }
}

struct WarningChip: View {
    let text: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(text)
        }
        .font(.subheadline)
        .foregroundStyle(.orange)
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color.orange.opacity(0.15), in: Capsule())
    }
}
