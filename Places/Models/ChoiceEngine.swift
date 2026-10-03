//
//  ChoiceAnswer.swift
//  Places
//
//  Created by Raymond Yang on 10/2/26.
//


import Foundation

/// What the person said about one question.
enum ChoiceAnswer: Hashable {
    case want    // yes, I want this
    case avoid   // no, or that's a deal-breaker
    case skip    // doesn't matter
}

/// One thing that happened in the conversation, in order.
struct ChoiceStep: Identifiable {
    enum Kind {
        case answer(key: String, answer: ChoiceAnswer)
        case notThisOne(UUID)
    }

    let id = UUID()
    let kind: Kind
}

struct ChoiceQuestion: Equatable {
    let key: String
    let name: String
    let kind: TagKind
    let section: String
    let definition: String
}

/// Everything derived from the steps so far.
struct ChoiceSnapshot {
    var wanted: [String] = []
    var avoided: [String] = []
    var answered = 0
    /// The places still in the running, best first.
    var contenders: [Restaurant] = []
    /// The next question to ask, or nil when it's time for a result.
    var question: ChoiceQuestion?
}

enum ChoiceEngine {
    static let maxQuestions = 20

    static func snapshot(restaurants: [Restaurant],
                         definitions: [TagDefinition],
                         steps: [ChoiceStep]) -> ChoiceSnapshot {
        var result = ChoiceSnapshot()
        var asked = Set<String>()
        var rejectedPlaces = Set<UUID>()

        for step in steps {
            switch step.kind {
            case .answer(let key, let answer):
                asked.insert(key)
                result.answered += 1
                switch answer {
                case .want: result.wanted.append(key)
                case .avoid: result.avoided.append(key)
                case .skip: break
                }
            case .notThisOne(let id):
                rejectedPlaces.insert(id)
            }
        }

        let validKeys = Set(definitions.map(\.key))
        func keys(_ restaurant: Restaurant) -> Set<String> {
            Set(restaurant.appliedTags.map(\.tagKey)).intersection(validKeys)
        }

        let wanted = Set(result.wanted)
        let avoided = Set(result.avoided)

        // A place is removed only if it explicitly has something you ruled out.
        // A place that merely lacks a tag stays, since a missing tag means "unknown".
        let alive = restaurants.filter {
            !rejectedPlaces.contains($0.id) && keys($0).isDisjoint(with: avoided)
        }

        // Keep the best matches for what you asked for.
        let scored = alive.map { (restaurant: $0, score: keys($0).intersection(wanted).count) }
        let best = scored.map { $0.score }.max() ?? 0
        var contenders = scored.filter { $0.score == best }.map { $0.restaurant }

        // Richer reviews first, then alphabetical.
        contenders.sort {
            if $0.appliedTags.count != $1.appliedTags.count {
                return $0.appliedTags.count > $1.appliedTags.count
            }
            if $0.statements.count != $1.statements.count {
                return $0.statements.count > $1.statements.count
            }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        result.contenders = contenders

        if result.answered < maxQuestions, contenders.count > 1 {
            result.question = bestQuestion(contenders: contenders,
                                           definitions: definitions,
                                           asked: asked)
        }
        return result
    }

    /// The tag or warning that splits the contenders closest to half and half.
    private static func bestQuestion(contenders: [Restaurant],
                                     definitions: [TagDefinition],
                                     asked: Set<String>) -> ChoiceQuestion? {
        var counts: [String: Int] = [:]
        for restaurant in contenders {
            for key in Set(restaurant.appliedTags.map(\.tagKey)) {
                counts[key, default: 0] += 1
            }
        }

        let total = Double(contenders.count)
        var best: TagDefinition?
        var bestDistance = Double.infinity

        // Definitions come in vocabulary order, so ties go to the earlier one.
        for definition in definitions {
            guard !asked.contains(definition.key),
                  let count = counts[definition.key],
                  count < contenders.count else { continue }
            let distance = abs(Double(count) / total - 0.5)
            if distance < bestDistance - 0.0001 {
                best = definition
                bestDistance = distance
            }
        }

        guard let best else { return nil }
        return ChoiceQuestion(key: best.key,
                              name: best.name,
                              kind: best.kind,
                              section: best.section,
                              definition: best.definition)
    }
}
