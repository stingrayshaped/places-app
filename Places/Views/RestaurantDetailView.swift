import SwiftUI
import SwiftData

struct RestaurantDetailView: View {
    @Bindable var restaurant: Restaurant
    @Query(sort: \TagDefinition.sortOrder) private var definitions: [TagDefinition]
    @State private var inspecting: TagDefinition?
    @State private var showingAddressFinder = false

    private var center: AnalysisCenter { .shared }

    var body: some View {
        List {
            Section("Summary") {
                summaryContent
            }

            if !appliedWarnings.isEmpty {
                Section("Warnings") {
                    FlowLayout {
                        ForEach(appliedWarnings) { definition in
                            Button {
                                inspecting = definition
                            } label: {
                                WarningChip(text: definition.name, isAI: isAI(definition))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            
            Section("Address") {
                addressContent
            }
            
            Section("Tags") {
                if !appliedTags.isEmpty {
                    FlowLayout {
                        ForEach(appliedTags) { definition in
                            Button {
                                inspecting = definition
                            } label: {
                                TagChip(text: definition.name, isAI: isAI(definition))
                            }
                            .buttonStyle(.plain)
                        }
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
            }
            
        }
        .navigationTitle(restaurant.name)
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { restaurant.updatedAt = .now }
        .sheet(item: $inspecting) { definition in
            TagDetailSheet(restaurant: restaurant, definition: definition)
        }
        .sheet(isPresented: $showingAddressFinder) {
            AddressFinderView(initialQuery: restaurant.name) { place in
                restaurant.apply(place)
            }
        }
    }

    // MARK: Applied tags and warnings

    private var appliedTags: [TagDefinition] { applied(.tag) }
    private var appliedWarnings: [TagDefinition] { applied(.warning) }

    private func applied(_ kind: TagKind) -> [TagDefinition] {
        let keys = Set(restaurant.appliedTags.map(\.tagKey))
        return definitions.filter { $0.kind == kind && keys.contains($0.key) }
    }

    private func isAI(_ definition: TagDefinition) -> Bool {
        restaurant.appliedTags.contains { $0.tagKey == definition.key && $0.source == .ai }
    }
    
    // MARK: Address and directions

    @ViewBuilder
    private var addressContent: some View {
        TextField("Address", text: $restaurant.address)

        Button {
            showingAddressFinder = true
        } label: {
            Label(restaurant.address.isEmpty ? "Find Address on Map" : "Look Up Address Again",
                  systemImage: "mappin.and.ellipse")
        }

        if !restaurant.address.isEmpty {
            Menu {
                Button("Driving", systemImage: "car.fill") {
                    MapsLauncher.openDirections(to: restaurant, mode: .driving)
                }
                Button("Walking", systemImage: "figure.walk") {
                    MapsLauncher.openDirections(to: restaurant, mode: .walking)
                }
                Button("Transit", systemImage: "tram.fill") {
                    MapsLauncher.openDirections(to: restaurant, mode: .transit)
                }
            } label: {
                Label("Directions", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
            } primaryAction: {
                MapsLauncher.openDirections(to: restaurant, mode: .driving)
            }

            Text(restaurant.hasVerifiedLocation
                 ? "Matched on the map. Tap Directions to drive there, or touch and hold for walking or transit."
                 : "Not matched on the map, so Directions will search for this address.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Summary

    @ViewBuilder
    private var summaryContent: some View {
        if center.isRunning(restaurant) {
            HStack {
                ProgressView()
                Text("Analyzing review…")
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

// MARK: - Chips

struct TagChip: View {
    let text: String
    var isAI = false

    var body: some View {
        HStack(spacing: 4) {
            Text(text)
            if isAI {
                Image(systemName: "sparkle")
                    .font(.caption2)
            }
        }
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
    var isAI = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(text)
            if isAI {
                Image(systemName: "sparkle")
                    .font(.caption2)
            }
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

// MARK: - Why was this applied?

struct EvidenceLine: Identifiable {
    let number: Int
    let statement: ReviewStatement
    var id: UUID { statement.id }
}

struct TagDetailSheet: View {
    @Bindable var restaurant: Restaurant
    let definition: TagDefinition
    @Environment(\.dismiss) private var dismiss

    private var application: TagApplication? {
        restaurant.appliedTags.first { $0.tagKey == definition.key }
    }

    var body: some View {
        NavigationStack {
            List {
                if !definition.definition.isEmpty {
                    Section("Meaning") {
                        Text(definition.definition)
                    }
                }

                Section("Why") {
                    whyContent
                }

                Section {
                    Button("Remove", role: .destructive) {
                        restaurant.removeTag(key: definition.key)
                        dismiss()
                    }
                } footer: {
                    Text("A removed tag won't be applied again automatically.")
                }
            }
            .navigationTitle(definition.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder
    private var whyContent: some View {
        if let application {
            switch application.source {
            case .manual:
                Text("Added by you.")
                    .foregroundStyle(.secondary)
            case .ai:
                let lines = evidenceLines(for: application)
                if lines.isEmpty {
                    Text("The statements that supported this have changed. Update the summary to check again.")
                        .foregroundStyle(.secondary)
                } else {
                    Label("Applied by AI from:", systemImage: "sparkles")
                        .foregroundStyle(.secondary)
                    ForEach(lines) { line in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text("\(line.number)")
                                .font(.callout.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(minWidth: 28, alignment: .trailing)
                            Text(line.statement.text)
                        }
                    }
                }
            }
        }
    }

    private func evidenceLines(for application: TagApplication) -> [EvidenceLine] {
        restaurant.statements.enumerated().compactMap { index, statement in
            application.evidence.contains(statement.id)
                ? EvidenceLine(number: index + 1, statement: statement)
                : nil
        }
    }
}
