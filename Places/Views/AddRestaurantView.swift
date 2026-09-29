import SwiftUI
import SwiftData

struct AddRestaurantView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var address = ""
    @FocusState private var focusedField: Field?
    
    enum Field { case name, address }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Restaurant Name", text: $name)
                    .focused($focusedField, equals: .name)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .address }

                TextField("Address", text: $address)
                    .focused($focusedField, equals: .address)
                    .submitLabel(.done)
                    .onSubmit { focusedField = nil }
            }
            .navigationTitle("New Restaurant")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func save() {
        modelContext.insert(Restaurant(name: name, address: address))
        dismiss()
    }
}
