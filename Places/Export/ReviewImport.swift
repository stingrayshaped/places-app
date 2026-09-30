//
//  ConflictPolicy.swift
//  Places
//
//  Created by Raymond Yang on 9/29/26.
//

import SwiftUI
import SwiftData
import Observation

enum ImportStatus {
    case new            // not in your list
    case update         // a newer version of one you have
    case upToDate       // identical to yours
    case newerHere      // you already have a newer version
}

@MainActor
enum ReviewImporter {

    /// Reviews with no author (old files) or your own author ID are yours.
    static func incomingIsMine(_ record: RestaurantRecord) -> Bool {
        record.authorID == nil || record.authorID == MyProfile.shared.authorID
    }

    static func status(of record: RestaurantRecord, existing: Restaurant?) -> ImportStatus {
        guard let existing else { return .new }
        let incoming = record.updatedAt.timeIntervalSince1970.rounded(.down)
        let local = existing.updatedAt.timeIntervalSince1970.rounded(.down)
        if incoming > local { return .update }
        if incoming == local { return .upToDate }
        return .newerHere
    }

    /// Adds new reviews and updates older copies. Returns how many were changed.
    @discardableResult
    static func importFile(_ file: ReviewFile,
                           replaceNewer: Bool,
                           adoptProfile: Bool,
                           into context: ModelContext) throws -> Int {
        if adoptProfile, let profile = file.profile {
            MyProfile.shared.adopt(id: profile.authorID, name: profile.name)
        }

        let existing = try context.fetch(FetchDescriptor<Restaurant>())
        let existingByID = Dictionary(existing.map { ($0.id, $0) },
                                      uniquingKeysWith: { first, _ in first })

        let definitions = try context.fetch(
            FetchDescriptor<TagDefinition>(sortBy: [SortDescriptor(\.sortOrder)])
        )
        var knownKeys = Set(definitions.map(\.key))
        var nextOrder = (definitions.map(\.sortOrder).max() ?? 0) + 1

        // Add any tags the file uses that this device doesn't have yet.
        for record in file.vocabulary where !knownKeys.contains(record.key) {
            let entry = TagDefinition(key: record.key, name: record.name, kind: record.kind,
                                      section: record.section, definition: record.definition,
                                      sortOrder: nextOrder)
            entry.aliases = record.aliases
            context.insert(entry)
            knownKeys.insert(record.key)
            nextOrder += 1
        }

        var changed = 0
        for record in file.restaurants {
            let match = existingByID[record.id]

            switch status(of: record, existing: match) {
            case .upToDate:
                continue
            case .newerHere where !replaceNewer:
                continue
            default:
                break
            }

            let target: Restaurant
            if let match {
                target = match
            } else {
                target = Restaurant(name: record.name, address: record.address)
                target.id = record.id            // reviews keep their identity
                context.insert(target)
            }
            fill(target, from: record, knownKeys: knownKeys)
            changed += 1
        }

        try context.save()
        return changed
    }

    private static func fill(_ target: Restaurant,
                             from record: RestaurantRecord,
                             knownKeys: Set<String>) {
        let mine = incomingIsMine(record)

        // Keep links from statements to their local recordings, if we have them.
        var audioByStatement: [UUID: String] = [:]
        for statement in target.statements {
            if let audio = statement.sourceAudio { audioByStatement[statement.id] = audio }
        }

        target.name = record.name
        target.address = record.address
        target.latitude = record.latitude
        target.longitude = record.longitude
        target.verifiedAddress = (record.latitude != nil && record.longitude != nil)
            ? record.address
            : ""
        target.createdAt = record.createdAt
        target.updatedAt = record.updatedAt

        target.authorID = mine ? nil : record.authorID
        target.authorName = mine ? "" : (record.authorName ?? "")
        target.receivedAt = mine ? nil : .now
        target.basedOnAuthorName = record.basedOnAuthorName ?? ""
        target.basedOnReviewID = record.basedOnReviewID

        target.statements = record.statements.map {
            ReviewStatement(id: $0.id, text: $0.text, sourceAudio: audioByStatement[$0.id])
        }
        target.summary = record.summary
        // The summary came with the file, so don't flag it as out of date.
        target.analyzedSource = record.summary.isEmpty ? "" : target.statementsSource

        target.appliedTags = record.tags
            .filter { knownKeys.contains($0.key) }
            .map {
                TagApplication(tagKey: $0.key, source: $0.source,
                               evidence: $0.evidence, appliedAt: $0.appliedAt)
            }
        target.rejectedTagKeys = mine ? (record.rejectedTagKeys ?? []) : []

        // Everything is now in place, so remember the fingerprint. This keeps
        // the date from moving until the content really changes.
        target.contentFingerprint = target.computeFingerprint()
    }
}

// MARK: - Receiving a file

struct PendingImport: Identifiable {
    let id = UUID()
    let file: ReviewFile
}

@MainActor
@Observable
final class ImportCenter {
    static let shared = ImportCenter()

    var pending: PendingImport?
    var errorMessage: String?

    /// Reads a file that was opened in the app or picked from Files.
    func load(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        do {
            let data = try Data(contentsOf: url)
            let file = try ReviewFile.decode(data)
            pending = PendingImport(file: file)

            // Files opened from AirDrop or Messages are copied into the app's Inbox
            // folder. Once read, that copy isn't needed. (Files picked with the
            // importer live elsewhere and are left alone.)
            if url.path.contains("/Inbox/") {
                try? FileManager.default.removeItem(at: url)
            }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? "Couldn't read that file."
        }
    }
}
