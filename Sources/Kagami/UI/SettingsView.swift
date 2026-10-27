import SwiftUI

/// Kagami's only setting: how it looks for updates.
struct SettingsView: View {
    let updates: UpdateService

    var body: some View {
        Form {
            Section {
                Picker("Updates", selection: Binding(
                    get: { updates.policy },
                    set: { updates.setPolicy($0) }
                )) {
                    ForEach(UpdatePolicy.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .disabled(!updates.isAvailable)

                LabeledContent("Version") {
                    HStack(spacing: 8) {
                        Text(verbatim: UpdateService.version()).foregroundStyle(.secondary)
                        if updates.isAvailable {
                            Button("Check Now") { updates.checkForUpdates() }
                                .disabled(!updates.canCheck)
                        }
                    }
                }
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    if updates.isAvailable {
                        Text(updates.policy.detail)
                        if let lastCheck = updates.lastCheck {
                            Text("Last checked \(lastCheck.formatted(date: .abbreviated, time: .shortened)).")
                        }
                    } else {
                        Text("This copy was built from source, so it does not update itself. Copies downloaded from the releases page do.")
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }
}
