//
//  TagPickerView.swift
//  Places
//
//  Created by Raymond Yang on 9/28/26.
//


import SwiftUI
import SwiftData

struct TagPickerView: View {
    @Bindable var restaurant: Restaurant
    @Query(sort: \TagDefinition.sortOrder) private var definitions: [TagDefinition]
    @State private var searchText = ""

    var body: some View {
        List {
            ForEach(groups, id: \.section) { group in
                Section(group.section) {
                    ForEach(group.items) { definition in
                        Button {
                            toggle(definition)
                        } label: {
                            row(for: definition)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search tags")
        .navigationTitle("Tags & Warnings")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Rows

    private func row(for definition: TagDefinition) -> some View {
        HStack(spacing: 10) {
            if definition.kind == .warning {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(definition.name)
                if !definition.definition.isEmpty {
                    Text(definition.definition)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if isApplied(definition) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(definition.kind == .warning ? Color.orange : Color.accentColor)
            }
        }
        .contentShape(Rectangle())
    }

    // MARK: Grouping and search

    private var visible: [TagDefinition] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return definitions }
        return definitions.filter {
            $0.name.localizedCaseInsensitiveContains(query)
            || $0.section.localizedCaseInsensitiveContains(query)
        }
    }

    /// Sections in vocabulary order, each with its items.
    private var groups: [(section: String, items: [TagDefinition])] {
        var order: [String] = []
        var buckets: [String: [TagDefinition]] = [:]
        for definition in visible {
            if buckets[definition.section] == nil { order.append(definition.section) }
            buckets[definition.section, default: []].append(definition)
        }
        return order.map { (section: $0, items: buckets[$0] ?? []) }
    }

    // MARK: Applying

    private func isApplied(_ definition: TagDefinition) -> Bool {
        restaurant.appliedTags.contains { $0.tagKey == definition.key }
    }

    private func toggle(_ definition: TagDefinition) {
        if isApplied(definition) {
            restaurant.removeTag(key: definition.key)
        } else {
            // In single-choice sections (like Price), applying one replaces the others.
            var siblings = Set<String>()
            if TagRules.singleChoiceSections.contains(definition.section) {
                siblings = Set(definitions
                    .filter { $0.section == definition.section }
                    .map(\.key))
            }
            restaurant.applyTagManually(key: definition.key, replacing: siblings)
        }
    }
}
