import SwiftData
import Foundation

struct ReviewStatement: Codable, Hashable, Identifiable {
    var id = UUID()
    var text: String
    var sourceAudio: String?   // file name of the recording this came from
}

@Model
final class Restaurant {
    @Attribute(.unique) var id: UUID
    var name: String
    var address: String
    var createdAt: Date
    var updatedAt: Date
    var statements: [ReviewStatement]

    // Derived by the model from the statements
    var summary: String = ""
    var analyzedSource: String = ""   // statement text the summary was built from

    // Tags and warnings, by vocabulary key
    var appliedTags: [TagApplication] = []
    var rejectedTagKeys: [String] = []   // tags the user removed; the AI won't re-apply them

    init(name: String, address: String = "") {
        self.id = UUID()
        self.name = name
        self.address = address
        self.createdAt = .now
        self.updatedAt = .now
        self.statements = []
    }

    var statementsSource: String {
        statements.map(\.text).joined(separator: "\n")
    }

    /// True when the statements have changed since the summary was written.
    var summaryIsStale: Bool {
        !statements.isEmpty && analyzedSource != statementsSource
    }
}
