//
//  ReviewPayload.swift
//  Places
//
//  Created by Raymond Yang on 9/30/26.
//


import Foundation
import SwiftData
import UniformTypeIdentifiers
import CoreTransferable

/// Packs a review into a message that can be pasted back into the app.
enum ReviewPayload {
    static let start = "[places:v1]"
    static let end = "[/places]"

    /// The message to send. Call from an action, not from a view body.
    @MainActor
    static func message(for restaurant: Restaurant, definitions: [TagDefinition]) throws -> String {
        let file = ReviewFile.make(restaurants: [restaurant], definitions: definitions)
        let json = try file.encoded(pretty: false)
        let packed = try (json as NSData).compressed(using: .lzfse) as Data
        let code = packed.base64EncodedString()

        return [
            ReviewText.markdown(for: restaurant),
            "To add this review in the Places app: copy this whole message, open Places, tap More, then Import Text from Clipboard, and tap Paste.",
            "\(start)\n\(code)\n\(end)"
        ].joined(separator: "\n\n")
    }

    /// Finds the review inside a pasted message.
    static func decode(from text: String) throws -> ReviewFile {
        guard let startRange = text.range(of: start, options: .caseInsensitive),
              let endRange = text.range(of: end, options: .caseInsensitive,
                                        range: startRange.upperBound..<text.endIndex) else {
            throw ReviewFileError.notAReviewFile
        }

        // Messaging apps sometimes add line breaks, so ignore all whitespace.
        let code = text[startRange.upperBound..<endRange.lowerBound]
            .filter { !$0.isWhitespace }

        guard let packed = Data(base64Encoded: String(code)),
              let json = try? (packed as NSData).decompressed(using: .lzfse) as Data else {
            throw ReviewFileError.notAReviewFile
        }
        return try ReviewFile.decode(json)
    }
}

/// The shareable text, built at the moment of sharing so it's always current.
nonisolated struct ReviewsTextShareItem: Transferable {
    let container: ModelContainer
    let restaurantID: UUID

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .utf8PlainText) { item in
            let text = try await MainActor.run { () throws -> String in
                let context = item.container.mainContext
                let id = item.restaurantID
                var descriptor = FetchDescriptor<Restaurant>(
                    predicate: #Predicate<Restaurant> { $0.id == id }
                )
                descriptor.fetchLimit = 1
                guard let restaurant = try context.fetch(descriptor).first else {
                    throw ReviewFileError.notAReviewFile
                }
                let definitions = try context.fetch(
                    FetchDescriptor<TagDefinition>(sortBy: [SortDescriptor(\.sortOrder)])
                )
                let message = try ReviewPayload.message(for: restaurant, definitions: definitions)
                try context.save()   // keeps any updated dates
                return message
            }
            return Data(text.utf8)
        }
    }
}