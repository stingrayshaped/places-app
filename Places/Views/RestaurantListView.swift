import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// A tag chip in the search field. Tags must be present; warnings must be absent.
struct TagFilter: Identifiable, Hashable {
    enum Mode: Hashable { case include, exclude }

    let key: String
    let name: String
    let mode: Mode

    var id: String { (mode == .include ? "has:" : "not:") + key }
}

struct RestaurantListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Restaurant.name) private var restaurants: [Restaurant]
    @Query(sort: \TagDefinition.sortOrder) private var definitions: [TagDefinition]

    @State private var searchText = ""
    @State private var tokens: [TagFilter] = []

    @State private var showingAddSheet = false
    @State private var importCenter = ImportCenter.shared
    @State private var showingImporter = false
    @State private var showingTextImport = false
    @State private var showingTags = false

    @State private var editMode: EditMode = .inactive
    @State private var selection = Set<UUID>()
    @State private var showingDeleteConfirm = false

    private var isSelecting: Bool { editMode.isEditing }

    var body: some View {
        NavigationStack {
            List(selection: $selection) {
                if !myReviews.isEmpty {
                    Section {
                        ForEach(myReviews) { restaurant in
                            row(for: restaurant)
                        }
                        .onDelete { deleteRestaurants(myReviews, at: $0) }
                    } header: {
                        if !friendGroups.isEmpty { Text("My Reviews") }
                    }
                }

                ForEach(friendGroups) { group in
                    Section("From \(group.name)") {
                        ForEach(group.items) { restaurant in
                            row(for: restaurant)
                        }
                        .onDelete { deleteRestaurants(group.items, at: $0) }
                    }
                }
            }
            .environment(\.editMode, $editMode)
            .navigationTitle(titleText)
            .searchable(text: $searchText, tokens: $tokens, prompt: "Search") { token in
                switch token.mode {
                case .include:
                    Label(token.name, systemImage: "tag")
                case .exclude:
                    Label("Without \(token.name)", systemImage: "nosign")
                }
            }
            .searchSuggestions {
                suggestionRows
            }
            .navigationDestination(for: Restaurant.self) { restaurant in
                RestaurantDetailView(restaurant: restaurant)
            }
            .navigationDestination(isPresented: $showingTags) {
                VocabularyEditorView()
            }
            .toolbar {
                if isSelecting {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(allSelected ? "Deselect All" : "Select All") {
                            toggleSelectAll()
                        }
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    if isSelecting {
                        Button("Done", action: finishSelecting)
                    } else {
                        moreMenu
                    }
                }

                // The same arrangement the Notes app uses: search on the left,
                // the new-item button on the right.
                DefaultToolbarItem(kind: .search, placement: .bottomBar)
                ToolbarSpacer(.flexible, placement: .bottomBar)
                ToolbarItem(placement: .bottomBar) {
                    Button("New Review", systemImage: "square.and.pencil") {
                        showingAddSheet = true
                    }
                }
            }
            .toolbar(isSelecting ? .hidden : .visible, for: .bottomBar)
            .safeAreaInset(edge: .bottom) {
                if isSelecting {
                    selectionBar
                }
            }
            .confirmationDialog(
                selection.count == 1 ? "Delete 1 review?" : "Delete \(selection.count) reviews?",
                isPresented: $showingDeleteConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive, action: deleteSelected)
            } message: {
                Text("This can't be undone. Friends who already have a copy of a review keep theirs.")
            }
            .sheet(isPresented: $showingAddSheet) {
                AddRestaurantView()
            }
            .sheet(isPresented: $showingTextImport) {
                ImportFromTextView()
            }
            .sheet(item: $importCenter.pending) { pending in
                ImportPreviewView(file: pending.file)
            }
            .fileImporter(
                isPresented: $showingImporter,
                allowedContentTypes: [.placesReview, .json, .data]
            ) { result in
                if case .success(let url) = result {
                    importCenter.load(url)
                }
            }
            .alert(
                "Couldn't Open File",
                isPresented: Binding(
                    get: { importCenter.errorMessage != nil },
                    set: { if !$0 { importCenter.errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(importCenter.errorMessage ?? "")
            }
            .overlay {
                if restaurants.isEmpty {
                    ContentUnavailableView(
                        "No Restaurants Yet",
                        systemImage: "fork.knife",
                        description: Text("Tap the New Review button to add your first one.")
                    )
                } else if shown.isEmpty {
                    if searchText.isEmpty {
                        ContentUnavailableView(
                            "No Matches",
                            systemImage: "tag.slash",
                            description: Text("No reviews match all of those tags.")
                        )
                    } else {
                        ContentUnavailableView.search(text: searchText)
                    }
                }
            }
            .task {
                VocabularySeeder.seedIfNeeded(in: modelContext)
            }
        }
    }

    // MARK: Title and menu

    private var titleText: String {
        guard isSelecting else { return "Restaurants" }
        return selection.isEmpty ? "Select Items" : "\(selection.count) Selected"
    }

    private var moreMenu: some View {
        Menu {
            Button {
                editMode = .active
            } label: {
                Label("Select Reviews", systemImage: "checkmark.circle")
            }
            .disabled(restaurants.isEmpty)

            Menu {
                Button {
                    showingImporter = true
                } label: {
                    Label("Import from File…", systemImage: "doc")
                }
                Button {
                    showingTextImport = true
                } label: {
                    Label("Import Text from Clipboard", systemImage: "doc.on.clipboard")
                }
            } label: {
                Label("Import", systemImage: "square.and.arrow.down")
            }

            Button {
                showingTags = true
            } label: {
                Label("Edit Tags", systemImage: "tag")
            }
        } label: {
            Label("More", systemImage: "ellipsis")
        }
    }

    // MARK: Search and tag filters

    private struct SuggestionItem: Identifiable {
        let filter: TagFilter
        let count: Int
        var id: String { filter.id }
    }

    private struct SuggestionGroup: Identifiable {
        let id: String
        let title: String
        let items: [SuggestionItem]
    }

    private var definitionsByKey: [String: TagDefinition] {
        Dictionary(definitions.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// Does this review satisfy every tag filter in the search field?
    private func passesTokens(_ restaurant: Restaurant) -> Bool {
        guard !tokens.isEmpty else { return true }
        let keys = Set(restaurant.appliedTags.map(\.tagKey))
        return tokens.allSatisfy { token in
            switch token.mode {
            case .include: keys.contains(token.key)
            case .exclude: !keys.contains(token.key)
            }
        }
    }

    /// Free text matches the name, address, reviewer, statements and tag names.
    private func matchesText(_ restaurant: Restaurant,
                             query: String,
                             lookup: [String: TagDefinition]) -> Bool {
        restaurant.name.localizedCaseInsensitiveContains(query)
        || restaurant.address.localizedCaseInsensitiveContains(query)
        || restaurant.authorName.localizedCaseInsensitiveContains(query)
        || restaurant.statements.contains { $0.text.localizedCaseInsensitiveContains(query) }
        || restaurant.appliedTags.contains { tag in
            guard let definition = lookup[tag.tagKey] else { return false }
            return definition.name.localizedCaseInsensitiveContains(query)
                || definition.aliases.contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    /// The reviews that match the tag filters and the search text.
    private var shown: [Restaurant] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let lookup = definitionsByKey
        return restaurants.filter { restaurant in
            passesTokens(restaurant)
            && (query.isEmpty || matchesText(restaurant, query: query, lookup: lookup))
        }
    }

    /// Filters worth offering: tags that some matching review has, and warnings
    /// that some matching review has (which choosing would hide).
    private var suggestionGroups: [SuggestionGroup] {
        // Count against the reviews that already pass the filters chosen so far,
        // so every suggestion actually changes the results.
        var counts: [String: Int] = [:]
        for restaurant in restaurants where passesTokens(restaurant) {
            for key in Set(restaurant.appliedTags.map(\.tagKey)) {
                counts[key, default: 0] += 1
            }
        }

        let chosen = Set(tokens.map(\.key))
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        func matches(_ definition: TagDefinition) -> Bool {
            guard !query.isEmpty else { return true }
            return definition.name.localizedCaseInsensitiveContains(query)
                || definition.aliases.contains { $0.localizedCaseInsensitiveContains(query) }
        }

        var order: [String] = []
        var buckets: [String: [SuggestionItem]] = [:]
        for definition in definitions
        where (counts[definition.key] ?? 0) > 0
            && !chosen.contains(definition.key)
            && matches(definition) {
            let isWarning = definition.kind == .warning
            let title = isWarning ? "Hide places with" : definition.section
            let filter = TagFilter(key: definition.key,
                                   name: definition.name,
                                   mode: isWarning ? .exclude : .include)
            if buckets[title] == nil { order.append(title) }
            buckets[title, default: []].append(
                SuggestionItem(filter: filter, count: counts[definition.key] ?? 0)
            )
        }
        return order.map { SuggestionGroup(id: $0, title: $0, items: buckets[$0] ?? []) }
    }

    @ViewBuilder
    private var suggestionRows: some View {
        ForEach(suggestionGroups) { group in
            Section(group.title) {
                ForEach(group.items) { item in
                    HStack {
                        Label(item.filter.name,
                              systemImage: item.filter.mode == .include ? "tag" : "nosign")
                        Spacer()
                        Text("\(item.count)")
                            .foregroundStyle(.secondary)
                    }
                    .searchCompletion(item.filter)
                }
            }
        }
    }

    // MARK: Selecting and sharing

    private var allSelected: Bool {
        !shown.isEmpty && shown.allSatisfy { selection.contains($0.id) }
    }

    private func toggleSelectAll() {
        let ids = Set(shown.map(\.id))
        if allSelected {
            selection.subtract(ids)
        } else {
            selection.formUnion(ids)
        }
    }

    private func finishSelecting() {
        selection.removeAll()
        editMode = .inactive
    }

    private func fileName(for chosen: [Restaurant]) -> String {
        chosen.count == 1 ? ExportNaming.safeFilename(chosen[0].name) : "Places Reviews"
    }

    /// Shown at the bottom while selecting, in place of search and New Review.
    private var selectionBar: some View {
        HStack {
            shareMenu
            Spacer()
            Button(role: .destructive) {
                showingDeleteConfirm = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .disabled(selection.isEmpty)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var shareMenu: some View {
        let chosen = restaurants.filter { selection.contains($0.id) }
        let name = fileName(for: chosen)

        return Menu {
            ShareLink(
                item: ReviewsShareItem(
                    container: modelContext.container,
                    restaurantIDs: chosen.map(\.id),
                    filename: name,
                    // Sharing everything doubles as a full backup.
                    backup: !restaurants.isEmpty && chosen.count == restaurants.count
                ),
                preview: SharePreview(name, image: Image(systemName: "fork.knife"))
            ) {
                Label("Share as File", systemImage: "doc.text")
            }

            ShareLink(item: ReviewText.markdown(for: chosen)) {
                Label("Share as Text", systemImage: "text.alignleft")
            }
        } label: {
            Label("Share", systemImage: "square.and.arrow.up")
        }
        .disabled(selection.isEmpty)
    }

    // MARK: Rows and grouping

    private func row(for restaurant: Restaurant) -> some View {
        NavigationLink(value: restaurant) {
            VStack(alignment: .leading, spacing: 2) {
                Text(restaurant.name)
                    .font(.headline)
                if !restaurant.address.isEmpty {
                    Text(restaurant.address)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if restaurant.isMine && !restaurant.basedOnAuthorName.isEmpty {
                    Text("Based on \(restaurant.basedOnAuthorName)'s review")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .deleteDisabled(isSelecting)
    }

    private var myReviews: [Restaurant] {
        shown.filter(\.isMine)
    }

    private struct FriendGroup: Identifiable {
        let id: String
        let name: String
        let items: [Restaurant]
    }

    /// Received reviews, one group per author name.
    private var friendGroups: [FriendGroup] {
        var groups: [String: [Restaurant]] = [:]
        for restaurant in shown where !restaurant.isMine {
            guard let authorID = restaurant.authorID else { continue }
            let name = restaurant.authorName
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            groups["\(authorID.uuidString)|\(name)", default: []].append(restaurant)
        }
        return groups
            .map { (key, items) -> FriendGroup in
                let name = items.first?.authorName
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return FriendGroup(id: key, name: name.isEmpty ? "Unknown" : name, items: items)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: Actions

    private func deleteRestaurants(_ list: [Restaurant], at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(list[index])
        }
    }

    private func deleteSelected() {
        for restaurant in restaurants where selection.contains(restaurant.id) {
            modelContext.delete(restaurant)
        }
        try? modelContext.save()
        finishSelecting()
    }
}

#Preview {
    RestaurantListView()
        .modelContainer(for: [Restaurant.self, TagDefinition.self], inMemory: true)
}
