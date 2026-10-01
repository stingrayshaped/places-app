import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct RestaurantListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Restaurant.name) private var restaurants: [Restaurant]

    @State private var showingAddSheet = false
    @State private var importCenter = ImportCenter.shared
    @State private var showingImporter = false
    @State private var showingExporter = false
    @State private var exportDocument: ReviewDocument?
    @State private var showingNameSheet = false
    @State private var showingTextImport = false

    var body: some View {
        NavigationStack {
            List {
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
            .navigationTitle("Restaurants")
            .navigationDestination(for: Restaurant.self) { restaurant in
                RestaurantDetailView(restaurant: restaurant)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        VocabularyEditorView()
                    } label: {
                        Label("Manage Tags", systemImage: "tag")
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Menu {
                        if MyProfile.shared.hasName {
                            ShareLink(
                                item: ReviewsShareItem(container: modelContext.container,
                                                       restaurantID: nil,
                                                       filename: "Places Reviews"),
                                preview: SharePreview("All Reviews", image: Image(systemName: "fork.knife"))
                            ) {
                                Label("Share All Reviews…", systemImage: "square.and.arrow.up.on.square")
                            }
                            .disabled(restaurants.isEmpty)
                        } else {
                            Button {
                                showingNameSheet = true
                            } label: {
                                Label("Set Your Name to Share…", systemImage: "person.crop.circle.badge.plus")
                            }
                        }

                        Button {
                            showingImporter = true
                        } label: {
                            Label("Import from File…", systemImage: "square.and.arrow.down")
                        }
                        
                        Button {
                            showingTextImport = true
                        } label: {
                            Label("Import Text from Clipboard", systemImage: "doc.on.clipboard")
                        }

                        Button {
                            exportAll()
                        } label: {
                            Label("Save Backup to Files…", systemImage: "externaldrive")
                        }
                        .disabled(restaurants.isEmpty)

                        Button {
                            showingNameSheet = true
                        } label: {
                            Label("Your Name…", systemImage: "person.crop.circle")
                        }
                    } label: {
                        Label("More", systemImage: "ellipsis.circle")
                    }

                    Button("Add", systemImage: "plus") {
                        showingAddSheet = true
                    }
                }
            }
            .sheet(isPresented: $showingAddSheet) {
                AddRestaurantView()
            }
            .sheet(isPresented: $showingNameSheet) {
                NameSheet()
            }
            .sheet(item: $importCenter.pending) { pending in
                ImportPreviewView(file: pending.file)
            }
            .sheet(isPresented: $showingTextImport) {
                ImportFromTextView()
            }
            .fileImporter(
                isPresented: $showingImporter,
                allowedContentTypes: [.placesReview, .json, .data]
            ) { result in
                if case .success(let url) = result {
                    importCenter.load(url)
                }
            }
            .fileExporter(
                isPresented: $showingExporter,
                document: exportDocument,
                contentType: .placesReview,
                defaultFilename: "Places Reviews"
            ) { _ in }
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
                        description: Text("Tap + to add your first one.")
                    )
                }
            }
            .task {
                VocabularySeeder.seedIfNeeded(in: modelContext)
            }
        }
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
    }

    private var myReviews: [Restaurant] {
        restaurants.filter(\.isMine)
    }

    private struct FriendGroup: Identifiable {
        let id: UUID
        let name: String
        let items: [Restaurant]
    }

    /// Received reviews, one group per author.
    private var friendGroups: [FriendGroup] {
        var groups: [UUID: [Restaurant]] = [:]
        for restaurant in restaurants where !restaurant.isMine {
            if let authorID = restaurant.authorID {
                groups[authorID, default: []].append(restaurant)
            }
        }
        return groups
            .map { id, items -> FriendGroup in
                // Use the name from the most recently received review.
                let newest = items.max {
                    ($0.receivedAt ?? .distantPast) < ($1.receivedAt ?? .distantPast)
                }
                let name = newest?.authorName
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return FriendGroup(id: id, name: name.isEmpty ? "Unknown" : name, items: items)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: Actions

    private func exportAll() {
        let descriptor = FetchDescriptor<TagDefinition>(sortBy: [SortDescriptor(\.sortOrder)])
        let definitions = (try? modelContext.fetch(descriptor)) ?? []
        let file = ReviewFile.make(restaurants: restaurants, definitions: definitions, backup: true)
        try? modelContext.save()
        guard let data = try? file.encoded() else { return }
        exportDocument = ReviewDocument(data: data)
        showingExporter = true
    }

    private func deleteRestaurants(_ list: [Restaurant], at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(list[index])
        }
    }
}

#Preview {
    RestaurantListView()
        .modelContainer(for: [Restaurant.self, TagDefinition.self], inMemory: true)
}
