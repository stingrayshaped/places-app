import SwiftUI
import SwiftData

struct RestaurantDetailView: View {
    @Bindable var restaurant: Restaurant
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TagDefinition.sortOrder) private var definitions: [TagDefinition]
    @Query private var allRestaurants: [Restaurant]

    @State private var inspecting: TagDefinition?
    @State private var showingAddressFinder = false
    @State private var showingNameSheet = false
    @State private var openedCopy: Restaurant?

    private var center: AnalysisCenter { .shared }
    private var profile: MyProfile { .shared }

    var body: some View {
        List {
            originSection

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

            if restaurant.isMine || !appliedTags.isEmpty {
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
                    if restaurant.isMine {
                        NavigationLink {
                            TagPickerView(restaurant: restaurant)
                        } label: {
                            Label("Edit Tags & Warnings", systemImage: "tag")
                        }
                    }
                }
            }

            Section {
                NavigationLink {
                    if restaurant.isMine {
                        ReviewEditorView(restaurant: restaurant)
                    } else {
                        ReadOnlyStatementsView(restaurant: restaurant)
                    }
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
                if restaurant.isMine {
                    TextField("Restaurant Name", text: $restaurant.name)
                } else {
                    LabeledContent("Name", value: restaurant.name)
                }
            }
        }
        .navigationTitle(restaurant.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                shareMenu
            }
        }
        .sheet(item: $inspecting) { definition in
            TagDetailSheet(restaurant: restaurant, definition: definition)
        }
        .sheet(isPresented: $showingAddressFinder) {
            AddressFinderView(initialQuery: restaurant.name) { place in
                restaurant.apply(place)
            }
        }
        .sheet(isPresented: $showingNameSheet) {
            NameSheet()
        }
        .navigationDestination(item: $openedCopy) { copy in
            RestaurantDetailView(restaurant: copy)
        }
    }

    // MARK: Who wrote it

    private var authorDisplayName: String {
        let name = restaurant.authorName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "an unknown author" : name
    }

    @ViewBuilder
    private var originSection: some View {
        if !restaurant.isMine {
            Section {
                Label("Review by \(authorDisplayName)", systemImage: "person.fill")
                if let received = restaurant.receivedAt {
                    Text("Received \(received.formatted(date: .abbreviated, time: .omitted))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                copyButton
            } footer: {
                Text("This is \(authorDisplayName)'s review, so it can't be edited. Make a copy to add your own opinion. Theirs stays as it is.")
            }
        } else if !restaurant.basedOnAuthorName.isEmpty {
            Section {
                Label("Based on \(restaurant.basedOnAuthorName)'s review",
                      systemImage: "arrow.turn.up.right")
            }
        }
    }

    /// A copy of this review that you already made, if any.
    private var existingCopy: Restaurant? {
        allRestaurants.first { $0.isMine && $0.basedOnReviewID == restaurant.id }
    }

    @ViewBuilder
    private var copyButton: some View {
        if let existing = existingCopy {
            Button {
                openedCopy = existing
            } label: {
                Label("Open My Copy", systemImage: "square.on.square")
            }
        } else {
            Button {
                makeCopy()
            } label: {
                Label("Make My Copy", systemImage: "square.on.square")
            }
        }
    }

    private func makeCopy() {
        let copy = restaurant.makeCopy()
        modelContext.insert(copy)
        try? modelContext.save()
        openedCopy = copy
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
        if restaurant.isMine {
            TextField("Address", text: $restaurant.address)

            Button {
                showingAddressFinder = true
            } label: {
                Label(restaurant.address.isEmpty ? "Find Address on Map" : "Look Up Address Again",
                      systemImage: "mappin.and.ellipse")
            }
        } else if restaurant.address.isEmpty {
            Text("No address")
                .foregroundStyle(.secondary)
        } else {
            Text(restaurant.address)
                .textSelection(.enabled)
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

    // MARK: Sharing

    private var shareMenu: some View {
        let name = ExportNaming.safeFilename(restaurant.name)

        return Menu {
            if profile.hasName {
                ShareLink(
                    item: ReviewsShareItem(container: modelContext.container,
                                           restaurantID: restaurant.id,
                                           filename: name),
                    preview: SharePreview(restaurant.name, image: Image(systemName: "fork.knife"))
                ) {
                    Label("Share as File", systemImage: "doc.text")
                }

                ShareLink(
                    item: ReviewsTextShareItem(container: modelContext.container,
                                               restaurantID: restaurant.id),
                    preview: SharePreview("\(restaurant.name) review")
                ) {
                    Label("Share as Text", systemImage: "text.alignleft")
                }
            } else {
                Button {
                    showingNameSheet = true
                } label: {
                    Label("Set Your Name to Share…", systemImage: "person.crop.circle.badge.plus")
                }
            }
        } label: {
            Label("Share", systemImage: "square.and.arrow.up")
        }
    }

    // MARK: Summary

    @ViewBuilder
    private var summaryContent: some View {
        if !restaurant.isMine {
            if restaurant.summary.isEmpty {
                Text("This review doesn't include a summary.")
                    .foregroundStyle(.secondary)
            } else {
                Text(restaurant.summary)
            }
        } else if center.isRunning(restaurant) {
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

                // Only the author can remove tags.
                if restaurant.isMine {
                    Section {
                        Button("Remove", role: .destructive) {
                            restaurant.removeTag(key: definition.key)
                            dismiss()
                        }
                    } footer: {
                        Text("A removed tag won't be applied again automatically.")
                    }
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
                Text(restaurant.isMine ? "Added by you." : "Added by the author.")
                    .foregroundStyle(.secondary)
            case .ai:
                let lines = evidenceLines(for: application)
                if lines.isEmpty {
                    Text("The statements that supported this have changed.")
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

// MARK: - Statements of a received review

struct ReadOnlyStatementsView: View {
    let restaurant: Restaurant

    var body: some View {
        List {
            ForEach(Array(restaurant.statements.enumerated()), id: \.element.id) { index, statement in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("\(index + 1)")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 28, alignment: .trailing)
                    Text(statement.text)
                        .textSelection(.enabled)
                }
            }
        }
        .navigationTitle("Statements")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if restaurant.statements.isEmpty {
                ContentUnavailableView(
                    "No Statements",
                    systemImage: "list.number",
                    description: Text("This review doesn't include any statements.")
                )
            }
        }
    }
}
