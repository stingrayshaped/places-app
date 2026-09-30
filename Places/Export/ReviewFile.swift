//
//  ReviewFile.swift
//  Places
//
//  Created by Raymond Yang on 9/29/26.
//


import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// Must match the exported type identifier in the target's Info tab.
    nonisolated static let placesReview = UTType(
        exportedAs: "com.stingrayshaped.places.review",
        conformingTo: .json
    )
}

// MARK: - File contents

struct ReviewFile: Codable {
    var format = "places-review"
    var version = 2
    var exportedAt = Date()
    var profile: ProfileRecord?          // only in backups
    var restaurants: [RestaurantRecord]
    var vocabulary: [VocabularyRecord]
}

struct ProfileRecord: Codable {
    var authorID: UUID
    var name: String
}

struct RestaurantRecord: Codable, Identifiable {
    var id: UUID
    var name: String
    var address: String
    var latitude: Double?
    var longitude: Double?
    var createdAt: Date
    var updatedAt: Date
    var summary: String
    var statements: [StatementRecord]
    var tags: [TagRecord]
    // Added in file format 2. Missing in older files.
    var authorID: UUID?
    var authorName: String?
    var basedOnAuthorName: String?
    var basedOnReviewID: UUID?
    var rejectedTagKeys: [String]?       // only in backups
}

struct StatementRecord: Codable {
    var id: UUID
    var text: String
}

struct TagRecord: Codable {
    var key: String
    var source: TagSource
    var evidence: [UUID]
    var appliedAt: Date
}

/// The definition of a tag, so an import can add ones the reader lacks.
struct VocabularyRecord: Codable {
    var key: String
    var name: String
    var kind: TagKind
    var section: String
    var definition: String
    var aliases: [String]
}

enum ReviewFileError: LocalizedError {
    case notAReviewFile
    case newerVersion

    var errorDescription: String? {
        switch self {
        case .notAReviewFile: "That isn't a Places review file."
        case .newerVersion: "That file was made by a newer version of the app. Update the app to open it."
        }
    }
}

// MARK: - Building, encoding, decoding

extension ReviewFile {
    static let currentVersion = 2

    /// Builds a file from the store. It also moves the date on each of your reviews
    /// forward if (and only if) its content changed since the last share.
    /// Call this from an action, never from inside a view's body.
    /// A backup includes the whole tag vocabulary, your vetoes, and your profile.
    @MainActor
    static func make(restaurants: [Restaurant],
                     definitions: [TagDefinition],
                     backup: Bool = false) -> ReviewFile {
        let me = MyProfile.shared
        var usedKeys = Set<String>()

        let records = restaurants.map { restaurant -> RestaurantRecord in
            restaurant.touchIfChanged()
            usedKeys.formUnion(restaurant.appliedTags.map(\.tagKey))
            return RestaurantRecord(
                id: restaurant.id,
                name: restaurant.name,
                address: restaurant.address,
                latitude: restaurant.latitude,
                longitude: restaurant.longitude,
                createdAt: restaurant.createdAt,
                updatedAt: restaurant.updatedAt,
                summary: restaurant.summary,
                statements: restaurant.statements.map { StatementRecord(id: $0.id, text: $0.text) },
                tags: restaurant.appliedTags.map {
                    TagRecord(key: $0.tagKey, source: $0.source,
                              evidence: $0.evidence, appliedAt: $0.appliedAt)
                },
                authorID: restaurant.authorID ?? me.authorID,
                authorName: restaurant.isMine ? me.displayName : restaurant.authorName,
                basedOnAuthorName: restaurant.basedOnAuthorName.isEmpty ? nil : restaurant.basedOnAuthorName,
                basedOnReviewID: restaurant.basedOnReviewID,
                rejectedTagKeys: backup ? restaurant.rejectedTagKeys : nil
            )
        }

        let vocabulary = definitions
            .filter { backup || usedKeys.contains($0.key) }
            .map {
                VocabularyRecord(key: $0.key, name: $0.name, kind: $0.kind,
                                 section: $0.section, definition: $0.definition,
                                 aliases: $0.aliases)
            }

        return ReviewFile(
            profile: backup ? ProfileRecord(authorID: me.authorID, name: me.displayName) : nil,
            restaurants: records,
            vocabulary: vocabulary
        )
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    static func decode(_ data: Data) throws -> ReviewFile {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let file = try? decoder.decode(ReviewFile.self, from: data),
              file.format == "places-review" else {
            throw ReviewFileError.notAReviewFile
        }
        guard file.version <= currentVersion else {
            throw ReviewFileError.newerVersion
        }
        return file
    }
}



// MARK: - For "Export All" (saves through Files)

nonisolated struct ReviewDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.placesReview]

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
