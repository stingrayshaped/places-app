//
//  TagEditView.swift
//  Places
//
//  Created by Raymond Yang on 9/28/26.
//


import SwiftUI
import SwiftData

struct TagEditView: View {
    let definition: TagDefinition?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \TagDefinition.sortOrder) private var definitions: [TagDefinition]

    @State private var name: String
    @State private var kind: TagKind
    @State private var section: String
    @State private var newSection = ""
    @State private var definitionText: String
    @State private var aliasesText: String

    init(definition: TagDefinition?) {
        self.definition = definition
        _name = State(initialValue: definition?.name ?? "")
        _kind = State(initialValue: definition?.kind ?? .tag)
        _section = State(initialValue: definition?.section ?? "")
        _definitionText = State(initialValue: definition?.definition ?? "")
        _aliasesText = State(initialValue: definition?.aliases.joined(separator: ", ") ?? "")
    }

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $name)
                if nameIsTaken {
                    Text("An entry with this name already exists.")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
                Picker("Type", selection: $kind) {
                    Text("Tag").tag(TagKind.tag)
                    Text("Warning").tag(TagKind.warning)
                }
                .pickerStyle(.segmented)
            }

            Section("Section") {
                Picker("Section", selection: $section) {
                    ForEach(existingSections, id: \.self) { Text($0).tag($0) }
                }
                TextField("Or create a new section", text: $newSection)
            }

            Section("Definition") {
                TextField("What counts as this?", text: $definitionText, axis: .vertical)
            }

            Section {
                TextField("Also known as", text: $aliasesText)
            } footer: {
                Text("Other phrases for the same thing, separated by commas. This will help the AI recognize it.")
            }
        }
        .navigationTitle(definition == nil ? "New Entry" : "Edit Entry")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                if definition == nil {
                    Button("Cancel") { dismiss() }
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save)
                    .disabled(!canSave)
            }
        }
        .onAppear {
            if section.isEmpty { section = existingSections.first ?? "" }
        }
    }

    // MARK: Validation

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespaces)
    }

    private var nameIsTaken: Bool {
        !trimmedName.isEmpty && definitions.contains {
            $0.name.caseInsensitiveCompare(trimmedName) == .orderedSame
            && $0.key != definition?.key
        }
    }

    private var effectiveSection: String {
        let typed = newSection.trimmingCharacters(in: .whitespaces)
        return typed.isEmpty ? section : typed
    }

    private var canSave: Bool {
        !trimmedName.isEmpty && !nameIsTaken && !effectiveSection.isEmpty
    }

    private var existingSections: [String] {
        definitions.groupedBySection().map(\.section)
    }

    // MARK: Saving

    private func save() {
        let aliases = aliasesText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        if let definition {
            definition.name = trimmedName
            definition.kind = kind
            definition.section = effectiveSection
            definition.definition = definitionText.trimmingCharacters(in: .whitespacesAndNewlines)
            definition.aliases = aliases
        } else {
            let key = TagRules.uniqueKey(for: trimmedName, existing: Set(definitions.map(\.key)))
            let order = (definitions.map(\.sortOrder).max() ?? 0) + 1
            let entry = TagDefinition(
                key: key,
                name: trimmedName,
                kind: kind,
                section: effectiveSection,
                definition: definitionText.trimmingCharacters(in: .whitespacesAndNewlines),
                sortOrder: order
            )
            entry.aliases = aliases
            modelContext.insert(entry)
        }
        try? modelContext.save()
        dismiss()
    }
}