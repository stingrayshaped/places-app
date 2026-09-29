//
//  VocabularyActions.swift
//  Places
//
//  Created by Raymond Yang on 9/28/26.
//


import SwiftData
import Foundation

enum VocabularyActions {

    /// How many restaurants have this tag or warning applied.
    static func usageCount(of definition: TagDefinition, in restaurants: [Restaurant]) -> Int {
        restaurants.filter { restaurant in
            restaurant.appliedTags.contains { $0.tagKey == definition.key }
        }.count
    }

    /// Removes the entry and strips it from every restaurant.
    @MainActor
    static func delete(_ definition: TagDefinition,
                       restaurants: [Restaurant],
                       context: ModelContext) {
        let key = definition.key
        for restaurant in restaurants where restaurant.appliedTags.contains(where: { $0.tagKey == key }) {
            restaurant.appliedTags.removeAll { $0.tagKey == key }
            restaurant.updatedAt = .now
        }
        context.delete(definition)
        try? context.save()
    }

    /// Folds `source` into `target`, then deletes `source`.
    @MainActor
    static func merge(_ source: TagDefinition,
                      into target: TagDefinition,
                      restaurants: [Restaurant],
                      context: ModelContext) {
        let sourceKey = source.key
        let targetKey = target.key

        for restaurant in restaurants {
            guard let index = restaurant.appliedTags.firstIndex(where: { $0.tagKey == sourceKey }) else { continue }

            if let existing = restaurant.appliedTags.firstIndex(where: { $0.tagKey == targetKey }) {
                // Already has the target: keep it and fold in the evidence.
                for id in restaurant.appliedTags[index].evidence
                where !restaurant.appliedTags[existing].evidence.contains(id) {
                    restaurant.appliedTags[existing].evidence.append(id)
                }
                restaurant.appliedTags.remove(at: index)
            } else {
                restaurant.appliedTags[index].tagKey = targetKey
            }
            restaurant.updatedAt = .now
        }

        // Remember the old name(s) as "also known as" on the survivor.
        var aliases = target.aliases
        for name in [source.name] + source.aliases {
            let alreadyKnown = name.caseInsensitiveCompare(target.name) == .orderedSame
                || aliases.contains { $0.caseInsensitiveCompare(name) == .orderedSame }
            if !alreadyKnown { aliases.append(name) }
        }
        target.aliases = aliases

        context.delete(source)
        try? context.save()
    }
}