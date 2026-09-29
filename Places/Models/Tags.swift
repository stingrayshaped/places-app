import SwiftData
import Foundation

enum TagKind: String, Codable {
    case tag, warning
}

enum TagSource: String, Codable {
    case manual, ai
}

/// A tag or warning applied to one restaurant.
struct TagApplication: Codable, Hashable, Identifiable {
    var id = UUID()
    var tagKey: String
    var source: TagSource
    var evidence: [UUID] = []   // ids of supporting statements (used once the AI applies tags)
    var appliedAt: Date = .now
}

/// One entry in the curated vocabulary.
@Model
final class TagDefinition {
    @Attribute(.unique) var key: String
    var name: String
    var kind: TagKind
    var section: String
    var definition: String
    var sortOrder: Int
    var aliases: [String] = []   // other phrases for the same thing

    init(key: String, name: String, kind: TagKind, section: String,
         definition: String, sortOrder: Int) {
        self.key = key
        self.name = name
        self.kind = kind
        self.section = section
        self.definition = definition
        self.sortOrder = sortOrder
    }
}

enum TagRules {
    /// Sections where only one tag can apply at a time.
    static let singleChoiceSections: Set<String> = ["Price"]

    /// "Open Late" becomes "open-late"; "$$" becomes "price-2".
    static func slug(_ name: String) -> String {
        if !name.isEmpty, name.allSatisfy({ $0 == "$" }) {
            return "price-\(name.count)"
        }
        var result = ""
        var lastWasDash = false
        for character in name.lowercased() {
            if character.isLetter || character.isNumber {
                result.append(character)
                lastWasDash = false
            } else if !lastWasDash && !result.isEmpty {
                result.append("-")
                lastWasDash = true
            }
        }
        if result.hasSuffix("-") { result.removeLast() }
        return result
    }

    /// A key that doesn't collide with any existing one.
    static func uniqueKey(for name: String, existing: Set<String>) -> String {
        let slugged = slug(name)
        let base = slugged.isEmpty ? "tag" : slugged
        var candidate = base
        var counter = 2
        while existing.contains(candidate) {
            candidate = "\(base)-\(counter)"
            counter += 1
        }
        return candidate
    }
}

extension Sequence where Element == TagDefinition {
    /// Groups entries by section, in the order sections first appear.
    func groupedBySection() -> [(section: String, items: [TagDefinition])] {
        var order: [String] = []
        var buckets: [String: [TagDefinition]] = [:]
        for definition in self {
            if buckets[definition.section] == nil { order.append(definition.section) }
            buckets[definition.section, default: []].append(definition)
        }
        return order.map { (section: $0, items: buckets[$0] ?? []) }
    }
}
