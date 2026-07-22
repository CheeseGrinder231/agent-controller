import AgentControllerMac
import SwiftUI

private enum CodexMapping: Equatable {
    case sessionPicker
    case projectStarter
    case pushToTalk
    case stop
    case scroll
}

struct CodexSettingsView: View {
    @ObservedObject var model: AppModel
    @State private var selectedMapping: CodexMapping = .pushToTalk

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsPageHeader(
                icon: "chevron.left.forwardslash.chevron.right",
                title: "Codex",
                subtitle: "Mappings used only while Codex is frontmost.",
                status: "5 mappings"
            )

            Form {
                Section("Controller Mappings") {
                    MappingSummaryRow(
                        input: "LB",
                        title: "Session Picker",
                        detail: "Choose an exact recent task before opening it.",
                        value: sessionCountValue,
                        actionLabel: "Details",
                        selected: selectedMapping == .sessionPicker,
                        disabled: model.isRecordingBinding,
                        select: { selectedMapping = .sessionPicker }
                    )
                    MappingSummaryRow(
                        input: "L3",
                        title: "Session Starter",
                        detail: "Choose a project, switch to Codex, then start a new task.",
                        value: projectCountValue,
                        actionLabel: "Details",
                        selected: selectedMapping == .projectStarter,
                        disabled: model.isRecordingBinding,
                        select: { selectedMapping = .projectStarter }
                    )
                    KeyboardMappingRow(
                        input: "RB",
                        title: "Push to Talk",
                        detail: "Hold to dictate into the Codex composer.",
                        action: .codexDictation,
                        chord: model.mappingSettings.codexDictation,
                        model: model,
                        select: { selectedMapping = .pushToTalk }
                    )
                    MappingSummaryRow(
                        input: "X",
                        title: "Stop",
                        detail: "Stop the current task, or the exact task opened by LB.",
                        value: stopMappingValue,
                        actionLabel: "Details",
                        selected: selectedMapping == .stop,
                        disabled: model.isRecordingBinding,
                        select: { selectedMapping = .stop }
                    )
                    MappingSummaryRow(
                        input: "R Stick",
                        title: "Scroll Session",
                        detail: "Continuous vertical scrolling with proportional speed.",
                        value: model.mappingSettings.codexScroll.enabled ? "On" : "Off",
                        actionLabel: "Edit",
                        selected: selectedMapping == .scroll,
                        disabled: model.isRecordingBinding,
                        select: { selectedMapping = .scroll }
                    )
                }

                mappingEditor

                Section {
                    DisclosureGroup("Diagnostics") {
                        SettingsStatusRow(
                            title: "Recent sessions",
                            value: sessionInventoryValue,
                            systemImage: sessionInventoryReady ? "checkmark.circle.fill" : nil,
                            color: sessionInventoryReady ? .green : .secondary
                        )
                        SettingsStatusRow(
                            title: "Recent projects",
                            value: projectInventoryValue,
                            systemImage: projectInventoryReady ? "checkmark.circle.fill" : nil,
                            color: projectInventoryReady ? .green : .secondary
                        )
                        SettingsStatusRow(
                            title: "RB dictation",
                            value: voiceStatusValue,
                            systemImage: voiceStatusValue == "Ready" ? "checkmark.circle.fill" : nil,
                            color: voiceStatusColor
                        )
                        SettingsStatusRow(
                            title: "X stop",
                            value: stopStatusValue,
                            systemImage: stopIsReady ? "checkmark.circle.fill" : nil,
                            color: stopIsReady ? .green : .secondary
                        )
                        LabeledContent("Last X attempt") {
                            Text(model.lastStopEvent)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.trailing)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        HStack {
                            Text("Latest event: \(model.lastEvent)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer()
                            Button("Refresh Codex") { model.refreshSessions() }
                                .disabled(model.inventoryState == .loading)
                        }
                    }
                }
            }
            .formStyle(.grouped)
        }
        .navigationTitle("Codex")
    }

    @ViewBuilder
    private var mappingEditor: some View {
        switch selectedMapping {
        case .sessionPicker:
            Section("LB · Session Picker") {
                LabeledContent("Choose with", value: "D-pad or left stick")
                LabeledContent("Commit", value: "Release LB")
                HStack {
                    Text("The list freezes for each hold. Preview never opens a task.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Preview Picker") { model.previewSelector() }
                }
            }
        case .projectStarter:
            Section("L3 · Session Starter") {
                LabeledContent("Choose with", value: "D-pad or left stick")
                LabeledContent("Commit", value: "Release L3")
                LabeledContent("Projects", value: "Recent Codex working folders")
                HStack {
                    Text("The project list freezes for each hold. Release switches to Codex mode, then opens its new-task page in the exact selected folder.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Preview Starter") { model.previewProjectSelector() }
                }
            }
        case .pushToTalk:
            KeyboardBindingCapturePanel(
                action: .codexDictation,
                currentChord: model.mappingSettings.codexDictation,
                model: model
            )
        case .stop:
            Section("X · Stop") {
                LabeledContent("Default", value: "Current Codex task")
                LabeledContent("Exact selector target") {
                    Text(model.managedStopSession?.title ?? "None")
                        .foregroundStyle(model.managedStopSession == nil ? .secondary : .primary)
                        .lineLimit(1)
                        .help(model.managedStopSession?.title ?? "No exact selector target")
                }
                Text("With no LB selector target, X stops the current Codex response, including tasks started from the L3 composer.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            KeyboardBindingCapturePanel(
                action: .codexStop,
                currentChord: model.mappingSettings.codexStop,
                model: model,
                sectionTitle: "Optional shortcut override"
            )
        case .scroll:
            Section("R Stick · Scroll Session") {
                Toggle("Enable vertical session scrolling", isOn: Binding(
                    get: { model.mappingSettings.codexScroll.enabled },
                    set: { model.setScrollEnabled($0) }
                ))
                Toggle("Invert vertical direction", isOn: Binding(
                    get: { model.mappingSettings.codexScroll.inverted },
                    set: { model.setScrollInverted($0) }
                ))
                LabeledContent("Speed") {
                    HStack(spacing: 8) {
                        Text("Slow")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Slider(value: Binding(
                            get: { model.mappingSettings.codexScroll.speed },
                            set: { model.setScrollSpeed($0) }
                        ), in: 0...1)
                        .frame(width: 180)
                        Text("Fast")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                HStack {
                    Text("Vertical intent only; release to neutral to stop. Scrolling never falls back to other apps.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Reset") { model.resetScrollSettings() }
                }
            }
        }
    }

    private var sessionInventoryReady: Bool {
        if case .ready(let count) = model.inventoryState { return count > 0 }
        return false
    }

    private var projectInventoryReady: Bool {
        if case .ready(let count) = model.projectInventoryState { return count > 0 }
        return false
    }

    private var sessionCountValue: String {
        model.recentSessions.isEmpty ? "No sessions" : "\(model.recentSessions.count) ready"
    }

    private var projectCountValue: String {
        if !model.accessibilityAuthorized { return "Needs Accessibility" }
        return model.recentProjects.isEmpty ? "No projects" : "\(model.recentProjects.count) ready"
    }

    private var sessionInventoryValue: String {
        switch model.inventoryState {
        case .idle: "Not loaded"
        case .loading: "Loading…"
        case .ready(let count): count == 1 ? "1 available" : "\(count) available"
        case .unavailable: "Unavailable"
        }
    }

    private var projectInventoryValue: String {
        switch model.projectInventoryState {
        case .idle: "Not loaded"
        case .loading: "Loading…"
        case .ready(let count): count == 1 ? "1 available" : "\(count) available"
        case .unavailable: "Unavailable"
        }
    }

    private var voiceStatusValue: String {
        if model.voiceReleasePending { return "Release pending" }
        if model.isDictating { return "Listening…" }
        if model.mappingSettings.codexDictation == nil { return "Needs recording" }
        if !model.accessibilityAuthorized { return "Needs Accessibility" }
        return "Ready"
    }

    private var voiceStatusColor: Color {
        switch voiceStatusValue {
        case "Ready": .green
        case "Release pending": .red
        default: .secondary
        }
    }

    private var stopStatusValue: String {
        if model.isStoppingCodex { return "Stopping…" }
        if model.managedStopSession != nil { return "Managed target ready" }
        if model.mappingSettings.codexStop != nil { return "Shortcut override ready" }
        return model.accessibilityAuthorized ? "Current task ready" : "Needs Accessibility"
    }

    private var stopIsReady: Bool {
        model.managedStopSession != nil || model.accessibilityAuthorized
    }

    private var stopMappingValue: String {
        if model.managedStopSession != nil { return "Exact task" }
        if model.mappingSettings.codexStop != nil { return "Custom" }
        return "Current"
    }
}
