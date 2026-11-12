import SwiftUI

struct HostEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var address: String
    @State private var accessID: String
    @State private var accessSecret: String
    let host: HostConfig
    let onSave: (HostConfig) -> Void

    init(host: HostConfig, onSave: @escaping (HostConfig) -> Void) {
        self.host = host
        self.onSave = onSave
        _name = State(initialValue: host.name)
        _address = State(initialValue: host.address)
        _accessID = State(initialValue: host.accessClientID ?? "")
        _accessSecret = State(initialValue: host.accessClientSecret ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    TextField("Address", text: $address)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.body.monospaced())
                }
                Section {
                    TextField("Client ID", text: $accessID)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Client secret", text: $accessSecret)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Cloudflare Access")
                } footer: {
                    Text("Only needed when the server is published through a tunnel.")
                }
            }
            .navigationTitle("Server")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var updated = host
                        updated.name = name.trimmingCharacters(in: .whitespaces)
                        updated.address = address.trimmingCharacters(in: .whitespaces)
                        updated.accessClientID = accessID.isEmpty ? nil : accessID
                        updated.accessClientSecret = accessSecret.isEmpty ? nil : accessSecret
                        onSave(updated)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
        .tint(RexTheme.mintDeep)
    }
}
