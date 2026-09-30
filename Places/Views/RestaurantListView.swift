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

    var body: some View {
        NavigationStack {
            List {
                ForEach(restaurants) { restaurant in
                    NavigationLink(value: restaurant) {
                        VStack(alignment: .leading) {
                            Text(restaurant.name)
                                .font(.headline)
                            if !restaurant.address.isEmpty {
                                Text(restaurant.address)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .onDelete(perform: deleteRestaurants)
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
            .sheet(item: $importCenter.pending) { pending in
                ImportPreviewView(file: pending.file)
            }
            .sheet(isPresented: $showingNameSheet) {
                NameSheet()
            }
            .fileImporter(
                isPresented: $showingImporter,
                allowedContentTypes: [.placesReview, .json]
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

    private func exportAll() {
        let descriptor = FetchDescriptor<TagDefinition>(sortBy: [SortDescriptor(\.sortOrder)])
        let definitions = (try? modelContext.fetch(descriptor)) ?? []
        let file = ReviewFile.make(restaurants: restaurants, definitions: definitions, backup: true)
        try? modelContext.save()
        guard let data = try? file.encoded() else { return }
        exportDocument = ReviewDocument(data: data)
        showingExporter = true
    }

    private func deleteRestaurants(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(restaurants[index])
        }
    }
}

#Preview {
    RestaurantListView()
        .modelContainer(for: [Restaurant.self, TagDefinition.self], inMemory: true)
}
