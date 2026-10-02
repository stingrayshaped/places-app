//
//  ReviewerPicker.swift
//  Places
//
//  Created by Raymond Yang on 10/1/26.
//


import SwiftUI
import SwiftData

/// The Reviewer dropdown, used on the Add Review page and on a review's detail screen.
struct ReviewerPicker: View {
    @Binding var selection: String
    /// Ask for a first name straight away when the list is empty.
    var promptWhenEmpty = false

    @State private var profile = MyProfile.shared
    @State private var showingNewName = false
    @State private var newName = ""
    @State private var showingNames = false

    private static let addNewTag = "\u{1}add-new-name"
    private static let editTag = "\u{1}edit-names"

    var body: some View {
        Picker("Reviewer", selection: pickerSelection) {
            if selection.isEmpty {
                Text("Choose a name").tag("")
            }
            // A review can keep a name that was later removed from the list.
            if !selection.isEmpty && !profile.reviewerNames.contains(selection) {
                Text(selection).tag(selection)
            }
            ForEach(profile.reviewerNames, id: \.self) { name in
                Text(name).tag(name)
            }
            Text("Add New Name…").tag(Self.addNewTag)
            if !profile.reviewerNames.isEmpty {
                Text("Edit Names…").tag(Self.editTag)
            }
        }
        .pickerStyle(.menu)
        .alert("New Reviewer Name", isPresented: $showingNewName) {
            TextField("Name", text: $newName)
            Button("Add", action: addName)
            Button("Cancel", role: .cancel) { newName = "" }
        } message: {
            Text("Names you add here appear in the Reviewer list.")
        }
        .sheet(isPresented: $showingNames) {
            ReviewerNamesView { old, new in
                if selection.caseInsensitiveCompare(old) == .orderedSame {
                    selection = new
                }
            }
        }
        .onAppear {
            if promptWhenEmpty && profile.reviewerNames.isEmpty {
                showingNewName = true
            }
        }
    }

    /// The two special menu items open something instead of changing the selection.
    private var pickerSelection: Binding<String> {
        Binding(
            get: { selection },
            set: { value in
                switch value {
                case Self.addNewTag:
                    newName = ""
                    showingNewName = true
                case Self.editTag:
                    showingNames = true
                default:
                    selection = value
                }
            }
        )
    }

    private func addName() {
        if let stored = MyProfile.shared.addReviewerName(newName) {
            selection = stored
        }
        newName = ""
    }
}

// MARK: - Managing the saved names

struct ReviewerNamesView: View {
    /// Called after a rename, with the old and new name.
    var onRename: (String, String) -> Void = { _, _ in }

    @Environment(\.dismiss) private var dismiss
    @Query private var restaurants: [Restaurant]
    @State private var profile = MyProfile.shared

    @State private var showingEntry = false
    @State private var entryOriginal: String?      // nil means adding a new name
    @State private var entryText = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(profile.reviewerNames, id: \.self) { name in
                        Button {
                            entryOriginal = name
                            entryText = name
                            errorMessage = nil
                            showingEntry = true
                        } label: {
                            HStack {
                                Text(name)
                                Spacer()
                                Text(countLabel(for: name))
                                    .foregroundStyle(.secondary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete(perform: remove)
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        if let errorMessage {
                            Text(errorMessage)
                                .foregroundStyle(.red)
                        }
                        Text("Tap a name to rename it. Renaming changes it on all your reviews that use it. Removing a name only takes it off this list. Reviews keep their name.")
                    }
                }
            }
            .overlay {
                if profile.reviewerNames.isEmpty {
                    ContentUnavailableView(
                        "No Names",
                        systemImage: "person",
                        description: Text("Tap + to add one.")
                    )
                }
            }
            .navigationTitle("Reviewer Names")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Add", systemImage: "plus") {
                        entryOriginal = nil
                        entryText = ""
                        errorMessage = nil
                        showingEntry = true
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert(entryOriginal == nil ? "New Reviewer Name" : "Rename Reviewer",
                   isPresented: $showingEntry) {
                TextField("Name", text: $entryText)
                Button(entryOriginal == nil ? "Add" : "Save", action: commitEntry)
                Button("Cancel", role: .cancel) { entryText = "" }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: Actions

    private func countLabel(for name: String) -> String {
        let count = restaurants.filter {
            $0.isMine && $0.authorName.caseInsensitiveCompare(name) == .orderedSame
        }.count
        return count == 1 ? "1 review" : "\(count) reviews"
    }

    private func commitEntry() {
        let proposed = entryText.trimmingCharacters(in: .whitespacesAndNewlines)
        entryText = ""
        guard !proposed.isEmpty else { return }

        // Adding a new name.
        guard let old = entryOriginal else {
            MyProfile.shared.addReviewerName(proposed)
            return
        }

        // Renaming an existing one.
        guard proposed != old else { return }
        guard let stored = MyProfile.shared.renameReviewer(old, to: proposed) else {
            errorMessage = "“\(proposed)” is already in the list."
            return
        }
        for restaurant in restaurants
        where restaurant.isMine && restaurant.authorName.caseInsensitiveCompare(old) == .orderedSame {
            restaurant.authorName = stored
        }
        onRename(old, stored)
    }

    private func remove(at offsets: IndexSet) {
        let names = offsets.map { profile.reviewerNames[$0] }
        for name in names {
            MyProfile.shared.removeReviewerName(name)
        }
    }
}