//
//  DeleteRequest.swift
//  Places
//
//  Created by Raymond Yang on 9/28/26.
//


import SwiftUI
import SwiftData

struct DeleteRequest: Identifiable {
    let key: String
    let name: String
    let usage: Int
    var id: String { key }
}

struct MergeRequest: Identifiable {
    let key: String
    let name: String
    let kind: TagKind
    var id: String { key }
}

struct VocabularyEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TagDefinition.sortOrder) private var definitions: [TagDefinition]
    @Query private var restaurants: [Restaurant]

    @State private var searchText = ""
    @State private var showingNew = false
    @State private var pendingDelete: DeleteRequest?
    @State private var mergeRequest: MergeRequest?

    var body: some View {
        List {
            ForEach(visible.groupedBySection(), id: \.section) { group in
                Section(group.section) {
                    ForEach(group.items) { definition in
                        NavigationLink {
                            TagEditView(definition: definition)
                        } label: {
                            row(for: definition)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                pendingDelete = DeleteRequest(
                                    key: definition.key,
                                    name: definition.name,
                                    usage: VocabularyActions.usageCount(of: definition, in: restaurants)
                                )
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            Button {
                                mergeRequest = MergeRequest(
                                    key: definition.key,
                                    name: definition.name,
                                    kind: definition.kind
                                )
                            } label: {
                                Label("Merge", systemImage: "arrow.triangle.merge")
                            }
                            .tint(.blue)
                        }
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search tags")
        .navigationTitle("Manage Tags")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Add", systemImage: "plus") { showingNew = true }
            }
        }
        .sheet(isPresented: $showingNew) {
            NavigationStack { TagEditView(definition: nil) }
        }
        .sheet(item: $mergeRequest) { request in
            NavigationStack { MergeTargetView(request: request) }
        }
        .confirmationDialog(
            "Delete this entry?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { request in
            Button("Delete “\(request.name)”", role: .destructive) {
                pendingDelete = nil
                if let definition = definitions.first(where: { $0.key == request.key }) {
                    VocabularyActions.delete(definition, restaurants: restaurants, context: modelContext)
                }
            }
        } message: { request in
            Text(request.usage == 0
                 ? "No restaurants use it."
                 : "It will be removed from \(request.usage) restaurant\(request.usage == 1 ? "" : "s").")
        }
    }

    // MARK: Rows and search

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
            Text("\(VocabularyActions.usageCount(of: definition, in: restaurants))")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private var visible: [TagDefinition] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return definitions }
        return definitions.filter { definition in
            definition.name.localizedCaseInsensitiveContains(query)
            || definition.section.localizedCaseInsensitiveContains(query)
            || definition.aliases.contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }
}

// MARK: - Choosing what to merge into

struct MergeTargetView: View {
    let request: MergeRequest

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \TagDefinition.sortOrder) private var definitions: [TagDefinition]
    @Query private var restaurants: [Restaurant]

    @State private var searchText = ""
    @State private var pendingTarget: TagDefinition?

    var body: some View {
        List {
            Section {
                Text("“\(request.name)” will be removed, and every restaurant that has it will get the entry you pick instead.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Merge into") {
                ForEach(candidates) { candidate in
                    Button {
                        pendingTarget = candidate
                    } label: {
                        HStack {
                            Text(candidate.name)
                            Spacer()
                            Text(candidate.section)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search")
        .navigationTitle("Merge Into…")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
        .confirmationDialog(
            "Merge these entries?",
            isPresented: Binding(
                get: { pendingTarget != nil },
                set: { if !$0 { pendingTarget = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingTarget
        ) { target in
            Button("Merge into “\(target.name)”", role: .destructive) {
                pendingTarget = nil
                if let source = definitions.first(where: { $0.key == request.key }) {
                    VocabularyActions.merge(source, into: target,
                                            restaurants: restaurants, context: modelContext)
                }
                dismiss()
            }
        } message: { target in
            Text("“\(request.name)” becomes “\(target.name)” everywhere and is then deleted.")
        }
    }

    /// Only entries of the same kind, so a tag never merges into a warning.
    private var candidates: [TagDefinition] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        return definitions.filter { definition in
            definition.kind == request.kind
            && definition.key != request.key
            && (query.isEmpty
                || definition.name.localizedCaseInsensitiveContains(query)
                || definition.section.localizedCaseInsensitiveContains(query))
        }
    }
}