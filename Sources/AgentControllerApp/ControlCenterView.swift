import SwiftUI

enum ControlCenterDestination: Hashable {
    case overview
    case inputMonitor
    case globalControls
    case codex
}

struct ControlCenterView: View {
    @ObservedObject var model: AppModel
    @State private var selection: ControlCenterDestination? = .globalControls

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section {
                    Label("Overview", systemImage: "gauge.with.dots.needle.33percent")
                        .tag(ControlCenterDestination.overview)
                    Label("Input Monitor", systemImage: "waveform.path.ecg.rectangle")
                        .tag(ControlCenterDestination.inputMonitor)
                    Label("Global Controls", systemImage: "globe")
                        .tag(ControlCenterDestination.globalControls)
                }

                Section("Apps") {
                    Label("Codex", systemImage: "chevron.left.forwardslash.chevron.right")
                        .tag(ControlCenterDestination.codex)
                }
            }
            .disabled(model.isRecordingBinding)
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 240)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                ControllerSidebarFooter(model: model)
            }
        } detail: {
            detail
        }
        .frame(minWidth: 760, minHeight: 520)
    }

    @ViewBuilder
    private var detail: some View {
        switch selection ?? .globalControls {
        case .overview:
            OverviewSettingsView(model: model, selection: $selection)
        case .inputMonitor:
            InputMonitorView(model: model)
        case .globalControls:
            GlobalControlsView(model: model)
        case .codex:
            CodexSettingsView(model: model)
        }
    }
}

private struct ControllerSidebarFooter: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            HStack(spacing: 10) {
                Image(systemName: model.controllerName == nil ? "gamecontroller" : "gamecontroller.fill")
                    .foregroundStyle(model.controllerName == nil ? Color.secondary : Color.green)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text(model.controllerName ?? "No controller")
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                    Text(model.isArmed ? "Controller enabled" : "Controller paused")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                Toggle("Controller enabled", isOn: $model.isArmed)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
        .background(.bar)
    }
}
