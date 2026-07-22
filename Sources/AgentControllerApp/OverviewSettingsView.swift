import SwiftUI

struct OverviewSettingsView: View {
    @ObservedObject var model: AppModel
    @Binding var selection: ControlCenterDestination?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsPageHeader(
                icon: "gamecontroller.fill",
                title: "Controller",
                subtitle: "One controller, with mappings scoped to the right place."
            )

            Form {
                Section("Controller") {
                    Toggle("Enable controller commands", isOn: $model.isArmed)
                    SettingsStatusRow(
                        title: "Hardware",
                        value: model.controllerName ?? "Not connected",
                        systemImage: model.controllerName == nil ? "circle" : "checkmark.circle.fill",
                        color: model.controllerName == nil ? .secondary : .green
                    )
                    SettingsStatusRow(
                        title: "Frontmost app",
                        value: model.context?.displayName ?? "Agent Controller"
                    )
                }

                Section("Configuration") {
                    Button {
                        selection = .globalControls
                    } label: {
                        Label("Edit controls that work in every app", systemImage: "globe")
                    }
                    Button {
                        selection = .codex
                    } label: {
                        Label("Edit Codex mappings", systemImage: "chevron.left.forwardslash.chevron.right")
                    }
                }

                Section("Latest Event") {
                    Text(model.lastEvent)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .formStyle(.grouped)
        }
        .navigationTitle("Overview")
    }
}
