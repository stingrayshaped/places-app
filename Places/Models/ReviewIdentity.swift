import Foundation
import Observation
import CryptoKit

// MARK: - You, as an author

@MainActor
@Observable
final class MyProfile {
    static let shared = MyProfile()

    /// Identifies this device's reviews to friends' apps.
    private(set) var authorID: UUID

    /// Names you've used for the Reviewer field, oldest first.
    private(set) var reviewerNames: [String]

    /// The reviewer chosen most recently. New reviews default to it.
    var lastReviewer: String {
        didSet { UserDefaults.standard.set(lastReviewer, forKey: Keys.lastReviewer) }
    }

    /// The name to use when nothing else says who a review is by.
    var displayName: String { lastReviewer }

    var hasName: Bool {
        !lastReviewer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private enum Keys {
        static let authorID = "myAuthorID"
        static let names = "reviewerNames"
        static let lastReviewer = "lastReviewer"
        static let oldName = "myDisplayName"   // from the earlier single-name setting
    }

    private init() {
        let defaults = UserDefaults.standard

        if let text = defaults.string(forKey: Keys.authorID), let id = UUID(uuidString: text) {
            authorID = id
        } else {
            let id = UUID()
            defaults.set(id.uuidString, forKey: Keys.authorID)
            authorID = id
        }

        var names = defaults.stringArray(forKey: Keys.names) ?? []
        var last = defaults.string(forKey: Keys.lastReviewer) ?? ""

        // Carry over the single name from the earlier version.
        if names.isEmpty, let old = defaults.string(forKey: Keys.oldName), !old.isEmpty {
            names = [old]
            if last.isEmpty { last = old }
            defaults.set(names, forKey: Keys.names)
        }
        if last.isEmpty { last = names.last ?? "" }

        reviewerNames = names
        lastReviewer = last
    }

    /// Adds a name to the list (ignoring capitalization duplicates)
    /// and returns the stored version of it.
    @discardableResult
    func addReviewerName(_ raw: String) -> String? {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }

        if let existing = reviewerNames.first(where: {
            $0.caseInsensitiveCompare(name) == .orderedSame
        }) {
            return existing
        }
        reviewerNames.append(name)
        UserDefaults.standard.set(reviewerNames, forKey: Keys.names)
        return name
    }

    /// Takes on an identity saved in a backup (for restoring on a new phone).
    func adopt(id: UUID, name: String) {
        authorID = id
        UserDefaults.standard.set(id.uuidString, forKey: Keys.authorID)
        if let stored = addReviewerName(name) {
            lastReviewer = stored
        }
    }
    
    /// Renames a name in the list. Returns the stored name, or nil if the new
    /// name is empty or already used by a different entry.
    @discardableResult
    func renameReviewer(_ old: String, to raw: String) -> String? {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty,
              let index = reviewerNames.firstIndex(where: {
                  $0.caseInsensitiveCompare(old) == .orderedSame
              }) else { return nil }

        let taken = reviewerNames.enumerated().contains {
            $0.offset != index && $0.element.caseInsensitiveCompare(name) == .orderedSame
        }
        guard !taken else { return nil }

        reviewerNames[index] = name
        UserDefaults.standard.set(reviewerNames, forKey: Keys.names)
        if lastReviewer.caseInsensitiveCompare(old) == .orderedSame {
            lastReviewer = name
        }
        return name
    }

    /// Takes a name off the list. Reviews that use it keep their name.
    func removeReviewerName(_ name: String) {
        reviewerNames.removeAll { $0.caseInsensitiveCompare(name) == .orderedSame }
        UserDefaults.standard.set(reviewerNames, forKey: Keys.names)
        if lastReviewer.caseInsensitiveCompare(name) == .orderedSame {
            lastReviewer = reviewerNames.last ?? ""
        }
    }
}

// MARK: - A reliable "last modified" date

extension Restaurant {
    /// A stable fingerprint of everything that gets shared.
    func computeFingerprint() -> String {
        let parts: [String] = [
            name,
            address,
            authorName,
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
    @MainActor
    func makeCopy() -> Restaurant {
        let copy = Restaurant(name: name, address: address)   // gets its own new id
        copy.authorName = MyProfile.shared.displayName
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
