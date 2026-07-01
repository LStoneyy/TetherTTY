import SwiftUI

struct ConnectionEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: ConnectionDraft

    let save: (ConnectionDraft) -> Void

    init(initialDraft: ConnectionDraft, save: @escaping (ConnectionDraft) -> Void) {
        _draft = State(initialValue: initialDraft)
        self.save = save
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Alias", text: $draft.alias)
                        .textContentType(.name)

                    TextField("Host", text: $draft.host)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    TextField("Port", text: $draft.port)
                        .keyboardType(.numberPad)
                } header: {
                    Text("Tether")
                }

                Section {
                    TextField("Username", text: $draft.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    SecureField("Password", text: $draft.password)
                        .textContentType(.password)
                } header: {
                    Text("Login")
                } footer: {
                    Text("Passwords are saved through the credential vault boundary, not inside the connection list model.")
                }

                Section {
                    Toggle("Favorite", isOn: $draft.isFavorite)
                }
            }
            .scrollContentBackground(.hidden)
            .background(AbyssBackground())
            .navigationTitle(draft.alias.isEmpty ? "New Tether" : "Edit Tether")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save(draft)
                        dismiss()
                    }
                    .disabled(!draft.isValid)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
