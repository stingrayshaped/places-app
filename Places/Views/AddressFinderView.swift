//
//  PlaceResult.swift
//  Places
//
//  Created by Raymond Yang on 9/29/26.
//

import SwiftUI
import MapKit

struct PlaceResult: Identifiable {
    let id = UUID()
    let name: String
    let address: String
    let latitude: Double
    let longitude: Double
}

struct AddressFinderView: View {
    let onSelect: (PlaceResult) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var query: String
    @AppStorage("addressSearchArea") private var area = ""
    @State private var results: [PlaceResult] = []
    @State private var isSearching = false
    @State private var message: String?

    init(initialQuery: String, onSelect: @escaping (PlaceResult) -> Void) {
        _query = State(initialValue: initialQuery)
        self.onSelect = onSelect
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Restaurant name", text: $query)
                        .submitLabel(.search)
                        .onSubmit { Task { await search() } }
                    TextField("City or neighborhood (optional)", text: $area)
                        .submitLabel(.search)
                        .onSubmit { Task { await search() } }
                    Button {
                        Task { await search() }
                    } label: {
                        Label("Search", systemImage: "magnifyingglass")
                    }
                } footer: {
                    Text("Adding a city helps when several places share a name.")
                }

                Section("Results") {
                    if isSearching {
                        HStack {
                            ProgressView()
                            Text("Searching…").foregroundStyle(.secondary)
                        }
                    } else if let message {
                        Text(message).foregroundStyle(.secondary)
                    }

                    ForEach(results) { place in
                        Button {
                            choose(place)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(place.name)
                                    .font(.headline)
                                Text(place.address)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Find Address")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task { await search() }
        }
    }

    // MARK: Searching

    private func search() async {
        let name = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let place = area.trimmingCharacters(in: .whitespacesAndNewlines)

        isSearching = true
        message = nil
        defer { isSearching = false }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = place.isEmpty ? name : "\(name) \(place)"
        request.resultTypes = .pointOfInterest
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: [
            .restaurant, .cafe, .bakery, .brewery, .winery, .foodMarket, .nightlife
        ])

        do {
            let response = try await MKLocalSearch(request: request).start()
            results = response.mapItems.compactMap { item -> PlaceResult? in
                guard let itemName = item.name,
                      let address = item.address?.fullAddress else { return nil }
                return PlaceResult(
                    name: itemName,
                    address: address,
                    latitude: item.location.coordinate.latitude,
                    longitude: item.location.coordinate.longitude
                )
            }
            if results.isEmpty {
                message = "No matches. Try adding a city or neighborhood."
            }
        } catch {
            print("Place search failed:", error)
            results = []
            message = "Couldn't search. Check your connection and try again."
        }
    }

    // MARK: Choosing

    private func choose(_ place: PlaceResult) {
        onSelect(place)
        dismiss()
    }
}

extension Restaurant {
    /// Saves a chosen map result as this restaurant's address and location.
    func apply(_ place: PlaceResult) {
        address = place.address
        latitude = place.latitude
        longitude = place.longitude
        verifiedAddress = place.address
        updatedAt = .now
    }
}
