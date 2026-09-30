//
//  NameSheet.swift
//  Places
//
//  Created by Raymond Yang on 9/29/26.
//


import SwiftUI

struct NameSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name: String

    init() {
        _name = State(initialValue: MyProfile.shared.displayName)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Your name", text: $name)
                        .textContentType(.name)
                        .submitLabel(.done)
                } footer: {
                    Text("Friends see this name on the reviews you share with them.")
                }
            }
            .navigationTitle("Your Name")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        MyProfile.shared.displayName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}