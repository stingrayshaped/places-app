//
//  ExportNaming.swift
//  Places
//
//  Created by Raymond Yang on 9/29/26.
//


import SwiftUI
import UniformTypeIdentifiers
import SwiftData

// MARK: - Helpers

enum ExportNaming {
    static func safeFilename(_ name: String) -> String {
        let banned = CharacterSet(charactersIn: "/\\:?*\"<>|")
        let cleaned = name
            .components(separatedBy: banned)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Restaurant" : cleaned
    }
}

extension Restaurant {
    /// The vocabulary entries of one kind that are applied to this restaurant.
    func appliedDefinitions(_ kind: TagKind, in definitions: [TagDefinition]) -> [TagDefinition] {
        let keys = Set(appliedTags.map(\.tagKey))
        return definitions.filter { $0.kind == kind && keys.contains($0.key) }
    }
}

// MARK: - Plain text (Markdown)

enum ReviewText {
    /// A readable dump: the restaurant's name and address, then the numbered statements.
    static func markdown(for restaurant: Restaurant) -> String {
        var sections = ["# \(restaurant.name)"]
        if !restaurant.address.isEmpty { sections.append(restaurant.address) }

        if !restaurant.statements.isEmpty {
            let list = restaurant.statements.enumerated()
                .map { "\($0.offset + 1). \($0.element.text)" }
                .joined(separator: "\n")
            sections.append(list)
        }
        return sections.joined(separator: "\n\n")
    }
    
    /// Several reviews in one message, separated by a divider.
    static func markdown(for restaurants: [Restaurant]) -> String {
        restaurants
            .map { markdown(for: $0) }
            .joined(separator: "\n\n---\n\n")
    }
}

// MARK: - Share items
/// A Places file built at the moment of sharing, so it's always current.
/// `restaurantIDs` picks which reviews to include. `backup` adds your whole
/// tag list, removed-tag memory and identity, for restoring on a new phone.
nonisolated struct ReviewsShareItem: Transferable {
    let container: ModelContainer
    let restaurantIDs: [UUID]
    let filename: String
    var backup = false

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .placesReview) { item in
            let data = try await MainActor.run { () throws -> Data in
                let context = item.container.mainContext
                var descriptor = FetchDescriptor<Restaurant>(sortBy: [SortDescriptor(\.name)])
                if !item.restaurantIDs.isEmpty {
                    let ids = item.restaurantIDs
                    descriptor.predicate = #Predicate<Restaurant> { ids.contains($0.id) }
                }
                let restaurants = try context.fetch(descriptor)
                let definitions = try context.fetch(
                    FetchDescriptor<TagDefinition>(sortBy: [SortDescriptor(\.sortOrder)])
                )
                let file = ReviewFile.make(restaurants: restaurants,
                                           definitions: definitions,
                                           backup: item.backup)
                try context.save()   // keeps any updated dates
                return try file.encoded()
            }
            let url = FileManager.default.temporaryDirectory
                .appending(path: "\(item.filename).placesreview")
            try data.write(to: url, options: .atomic)
            return SentTransferredFile(url)
        }
    }
}
