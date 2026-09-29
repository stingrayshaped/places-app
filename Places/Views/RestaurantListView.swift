import SwiftUI
import SwiftData

struct RestaurantListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Restaurant.name) private var restaurants: [Restaurant]
    @State private var showingAddSheet = false

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
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add", systemImage: "plus") {
                        showingAddSheet = true
                    }
                }
            }
            .sheet(isPresented: $showingAddSheet) {
                AddRestaurantView()
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
