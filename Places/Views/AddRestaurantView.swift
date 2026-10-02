import SwiftUI
import SwiftData

struct AddRestaurantView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    private enum Field { case name, address }
    @FocusState private var focusedField: Field?

    @State private var reviewer: String

    @State private var name = ""
    @State private var address = ""
    @State private var selectedPlace: PlaceResult?
    @State private var officialName: String?
    @State private var showingAddressFinder = false

    init() {
        _reviewer = State(initialValue: MyProfile.shared.lastReviewer)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ReviewerPicker(selection: $reviewer, promptWhenEmpty: true)
                }

                Section {
                    TextField("Restaurant Name", text: $name)
                        .focused($focusedField, equals: .name)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .address }

                    TextField("Address", text: $address)
                        .focused($focusedField, equals: .address)
                        .submitLabel(.done)
                        .onSubmit { focusedField = nil }
                }

                Section {
                    Button {
                        focusedField = nil
                        showingAddressFinder = true
                    } label: {
                        Label("Find Address on Map", systemImage: "mappin.and.ellipse")
                    }
                    .disabled(trimmedName.isEmpty)

                    if let officialName {
                        Button {
                            name = officialName
                            self.officialName = nil
                        } label: {
                            Label("Use the name “\(officialName)”", systemImage: "textformat")
                        }
                    }

                    if isMatched {
                        Label("Matched on the map", systemImage: "checkmark.circle")
                            .foregroundStyle(.secondary)
                    }
                } footer: {
                    Text("Enter the restaurant's name, then search to fill in its exact address.")
                }
            }
            .navigationTitle("New Restaurant")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(trimmedName.isEmpty || reviewer.isEmpty)
                }
            }
            .sheet(isPresented: $showingAddressFinder) {
                AddressFinderView(initialQuery: trimmedName) { place in
                    selectedPlace = place
                    address = place.address
                    officialName = place.name.caseInsensitiveCompare(trimmedName) == .orderedSame
                        ? nil
                        : place.name
                }
            }
        }
    }

    // MARK: Helpers

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// True while the address text is still the one the map result gave us.
    private var isMatched: Bool {
        guard let selectedPlace else { return false }
        return !address.isEmpty && selectedPlace.address == address
    }

    private func save() {
        let restaurant = Restaurant(
            name: trimmedName,
            address: address.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        restaurant.authorName = reviewer
        MyProfile.shared.lastReviewer = reviewer

        if let selectedPlace, isMatched {
            restaurant.apply(selectedPlace)
        }
        modelContext.insert(restaurant)
        dismiss()
    }
}
