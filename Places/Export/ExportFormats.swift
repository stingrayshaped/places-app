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

// MARK: - Contact card (.vcf)

enum ContactCard {
    static func vcard(for restaurant: Restaurant, definitions: [TagDefinition]) -> String {
        var lines = [
            "BEGIN:VCARD",
            "VERSION:3.0",
            "PRODID:-//Places//Restaurant Review//EN",
            "N:;;;;",
            "FN:\(escape(restaurant.name))",
            "ORG:\(escape(restaurant.name))",
            "X-ABShowAs:COMPANY"
        ]

        if !restaurant.address.isEmpty {
            lines.append("ADR;TYPE=WORK:;;\(escape(restaurant.address));;;;")
        }
        if restaurant.hasVerifiedLocation,
           let latitude = restaurant.latitude,
           let longitude = restaurant.longitude {
            lines.append("GEO:\(latitude);\(longitude)")
        }

        let warnings = restaurant.appliedDefinitions(.warning, in: definitions).map(\.name)
        let tags = restaurant.appliedDefinitions(.tag, in: definitions).map(\.name)

        var noteParts: [String] = []
        if !restaurant.summary.isEmpty { noteParts.append(restaurant.summary) }
        if !warnings.isEmpty { noteParts.append("Warnings: " + warnings.joined(separator: ", ")) }
        if !tags.isEmpty { noteParts.append("Tags: " + tags.joined(separator: ", ")) }
        if !noteParts.isEmpty {
            lines.append("NOTE:\(escape(noteParts.joined(separator: "\n\n")))")
        }

        lines.append("END:VCARD")
        return lines.map(fold).joined(separator: "\r\n") + "\r\n"
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: ",", with: "\\,")
            .replacingOccurrences(of: "\n", with: "\\n")
    }

    /// vCard lines are supposed to wrap at about 75 characters.
    private static func fold(_ line: String) -> String {
        var result = ""
        var count = 0
        for character in line {
            if count >= 72 {
                result += "\r\n "
                count = 1
            }
            result.append(character)
            count += 1
        }
        return result
    }
}

// MARK: - Plain text (Markdown)

enum ReviewText {
    static func markdown(for restaurant: Restaurant, definitions: [TagDefinition]) -> String {
        var sections = ["# \(restaurant.name)"]
        if !restaurant.address.isEmpty { sections.append(restaurant.address) }

        let warnings = restaurant.appliedDefinitions(.warning, in: definitions).map(\.name)
        let tags = restaurant.appliedDefinitions(.tag, in: definitions).map(\.name)
        if !warnings.isEmpty { sections.append("**Warnings:** " + warnings.joined(separator: ", ")) }
        if !tags.isEmpty { sections.append("**Tags:** " + tags.joined(separator: ", ")) }

        if !restaurant.summary.isEmpty {
            sections.append("## Summary\n\(restaurant.summary)")
        }
        if !restaurant.statements.isEmpty {
            let list = restaurant.statements.enumerated()
                .map { "\($0.offset + 1). \($0.element.text)" }
                .joined(separator: "\n")
            sections.append("## Statements\n\(list)")
        }
        return sections.joined(separator: "\n\n")
    }
}

// MARK: - Share items

/// A Places file built at the moment of sharing, so it's always current.
/// Pass a restaurantID to share one review, or nil to share them all.
nonisolated struct ReviewsShareItem: Transferable {
    let container: ModelContainer
    let restaurantID: UUID?
    let filename: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .placesReview) { item in
            let data = try await MainActor.run { () throws -> Data in
                let context = item.container.mainContext
                var descriptor = FetchDescriptor<Restaurant>(sortBy: [SortDescriptor(\.name)])
                if let id = item.restaurantID {
                    descriptor.predicate = #Predicate<Restaurant> { $0.id == id }
                }
                let restaurants = try context.fetch(descriptor)
                let definitions = try context.fetch(
                    FetchDescriptor<TagDefinition>(sortBy: [SortDescriptor(\.sortOrder)])
                )
                let file = ReviewFile.make(restaurants: restaurants, definitions: definitions)
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

/// The restaurant as a contact card.
nonisolated struct ContactCardItem: Transferable {
    let vcard: String
    let filename: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .vCard) { item in
            let url = FileManager.default.temporaryDirectory
                .appending(path: "\(item.filename).vcf")
            try item.vcard.write(to: url, atomically: true, encoding: .utf8)
            return SentTransferredFile(url)
        }
    }
}
