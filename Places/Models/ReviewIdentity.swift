//
//  MyProfile.swift
//  Places
//
//  Created by Raymond Yang on 9/29/26.
//


import Foundation
import Observation
import CryptoKit

// MARK: - You, as an author

@MainActor
@Observable
final class MyProfile {
    static let shared = MyProfile()

    private(set) var authorID: UUID

    var displayName: String {
        didSet { UserDefaults.standard.set(displayName, forKey: "myDisplayName") }
    }

    var hasName: Bool {
        !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private init() {
        let defaults = UserDefaults.standard
        if let text = defaults.string(forKey: "myAuthorID"), let id = UUID(uuidString: text) {
            authorID = id
        } else {
            let id = UUID()
            defaults.set(id.uuidString, forKey: "myAuthorID")
            authorID = id
        }
        displayName = defaults.string(forKey: "myDisplayName") ?? ""
    }

    /// Takes on an identity saved in a backup (for restoring on a new phone).
    func adopt(id: UUID, name: String) {
        authorID = id
        UserDefaults.standard.set(id.uuidString, forKey: "myAuthorID")
        displayName = name
    }
}

// MARK: - A reliable "last modified" date

extension Restaurant {
    /// A stable fingerprint of everything that gets shared.
    func computeFingerprint() -> String {
        let parts: [String] = [
            name,
            address,
            "\(latitude ?? 0),\(longitude ?? 0)",
            summary,
            statements.map(\.text).joined(separator: "\n"),
            appliedTags.map(\.tagKey).sorted().joined(separator: ",")
        ]
        let digest = SHA256.hash(data: Data(parts.joined(separator: "\u{1F}").utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Moves updatedAt forward only if the shared content really changed.
    /// Reviews received from someone else are never touched.
    func touchIfChanged() {
        guard isMine else { return }
        let current = computeFingerprint()
        guard current != contentFingerprint else { return }
        contentFingerprint = current
        updatedAt = Date(timeIntervalSince1970: Date.now.timeIntervalSince1970.rounded(.down))
    }
}

// MARK: - Making your own copy of someone's review

extension Restaurant {
    /// A new review of yours that starts out as a copy of this one.
    func makeCopy() -> Restaurant {
        let copy = Restaurant(name: name, address: address)   // gets its own new id
        copy.latitude = latitude
        copy.longitude = longitude
        copy.verifiedAddress = verifiedAddress
        copy.statements = statements.map {
            ReviewStatement(id: $0.id, text: $0.text, sourceAudio: nil)
        }
        copy.summary = summary
        copy.analyzedSource = summary.isEmpty ? "" : copy.statementsSource
        copy.appliedTags = appliedTags
        copy.basedOnAuthorName = isMine ? basedOnAuthorName : authorName
        copy.basedOnReviewID = id
        copy.contentFingerprint = copy.computeFingerprint()
        return copy
    }
}
