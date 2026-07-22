import AgentControllerMac
import SwiftUI

private enum GlobalEditableMapping: Equatable {
    case tab
    case enter

    var action: ControllerMappingAction {
        switch self {
        case .tab: .globalTab
        case .enter: .globalEnter
        }
    }
}

struct GlobalControlsView: View {
    @ObservedObject var model: AppModel
    @State private var selectedMapping: GlobalEditableMapping = .enter

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsPageHeader(
                icon: "globe",
                title: "Global Controls",
                subtitle: "Navigation controls available from every app.",
                status: "LT + A / RT"
            )

            Form {
                Section("Keyboard Controls") {
                    GlobalMappingRow(
                        input: "LT",
                        title: "Command Modifier",
                        detail: "Hold Command globally; release LT to commit the app selection."
                    )
                    KeyboardMappingRow(
                        input: "RT",
                        title: "Tab",
                        detail: "Pulse Tab, or cycle apps while LT holds Command.",
                        action: .globalTab,
                        chord: model.mappingSettings.globalTab,
                        model: model,
                        select: { selectedMapping = .tab }
                    )
                    KeyboardMappingRow(
                        input: "A",
                        title: "Enter / Submit",
                        detail: "Pulse Enter. Hold LT with A for Command + Enter.",
                        action: .globalEnter,
                        chord: model.mappingSettings.globalEnter,
                        model: model,
                        select: { selectedMapping = .enter }
                    )
                }

                KeyboardBindingCapturePanel(
                    action: selectedMapping.action,
                    currentChord: model.mappingSettings.chord(for: selectedMapping.action),
                    model: model
                )

                Section {
                    GlobalMappingRow(
                        input: "Y",
                        title: "Open Agent Controller",
                        detail: "Bring this configuration window forward."
                    )
                    GlobalMappingRow(
                        input: "B",
                        title: "Cancel Active Command",
                        detail: "Cancel a selector or binding capture, or retry a pending key release."
                    )
                    GlobalMappingRow(
                        input: "D-pad / L",
                        title: "Navigate Active Selector",
                        detail: "Move through whichever controller selector is open."
                    )
                } header: {
                    Text("Fixed Controller Actions")
                } footer: {
                    Text("Controller inputs stay fixed in this MVP. Click a keycap binding to record its keyboard output.")
                }

                Section("Permission") {
                    LabeledContent("Accessibility") {
                        HStack(spacing: 8) {
                            Text(model.accessibilityAuthorized ? "Allowed" : "Required")
                                .foregroundStyle(model.accessibilityAuthorized ? Color.green : Color.secondary)
                            if !model.accessibilityAuthorized {
                                Button("Allow") { model.requestAccessibilityAuthorization() }
                            }
                        }
                    }
                    if model.globalReleasePending {
                        Text("A global key release is pending. Press B or pause the controller before another command.")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .formStyle(.grouped)
        }
        .navigationTitle("Global Controls")
    }
}
