import AgentControllerCore
import SwiftUI

struct InputMonitorView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsPageHeader(
                icon: "waveform.path.ecg.rectangle",
                title: "Input Monitor",
                subtitle: "Controller input, semantic routing, and adapter outcomes.",
                status: model.controllerName == nil ? "Waiting" : "Live",
                statusColor: model.controllerName == nil ? .secondary : .green
            )

            VStack(spacing: 0) {
                contextBar
                Divider()
                activityHeader
                Divider()
                activity
                Divider()
                privacyFooter
            }
            .background(.background)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(.separator, lineWidth: 1)
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .navigationTitle("Input Monitor")
    }

    private var contextBar: some View {
        HStack(spacing: 18) {
            MonitorContextItem(
                label: "Controller",
                value: model.controllerName ?? "Not connected",
                systemImage: "gamecontroller"
            )
            MonitorContextItem(
                label: "Frontmost app",
                value: model.context?.displayName ?? "System",
                systemImage: "macwindow"
            )
            MonitorContextItem(
                label: "Commands",
                value: model.isArmed ? "Enabled" : "Paused",
                systemImage: model.isArmed ? "checkmark.circle" : "pause.circle"
            )
            Spacer(minLength: 0)
        }
        .padding(14)
    }

    private var activityHeader: some View {
        HStack {
            Text("Recent Activity")
                .font(.headline)
            Text("Newest first")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Clear") { model.clearInputMonitor() }
                .disabled(model.inputMonitorEvents.isEmpty)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var activity: some View {
        if model.inputMonitorEvents.isEmpty {
            ContentUnavailableView(
                "No Controller Input Yet",
                systemImage: "gamecontroller",
                description: Text("Use a mapped controller control to see how it resolves.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(model.inputMonitorEvents) { event in
                        InputMonitorEventRow(event: event)
                        if event.id != model.inputMonitorEvents.last?.id {
                            Divider().padding(.leading, 96)
                        }
                    }
                }
            }
        }
    }

    private var privacyFooter: some View {
        Label(
            "Process-local diagnostics only. Prompts, session titles, typed keys, and accessibility content are never recorded.",
            systemImage: "lock.shield"
        )
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(12)
    }
}

private struct MonitorContextItem: View {
    let label: String
    let value: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
            }
        }
    }
}

private struct InputMonitorEventRow: View {
    let event: InputMonitorEvent

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(event.occurredAt.formatted(date: .omitted, time: .standard))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .leading)

            ControllerInputBadge(label: event.input.displayName)

            VStack(alignment: .leading, spacing: 2) {
                Text(event.action.displayName)
                    .font(.callout.weight(.medium))
                Text("\(event.gesture.displayName) · \(event.route) · \(event.applicationName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            HStack(alignment: .top, spacing: 6) {
                Image(systemName: statusImage)
                    .foregroundStyle(statusColor)
                    .frame(width: 14)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(event.status.displayName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(statusColor)
                    Text(event.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: 210, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }

    private var statusImage: String {
        switch event.status {
        case .observed: "circle.dotted"
        case .routed: "arrow.right.circle"
        case .completed: "checkmark.circle.fill"
        case .blocked: "slash.circle.fill"
        case .cancelled: "xmark.circle"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    private var statusColor: Color {
        switch event.status {
        case .observed, .routed: .secondary
        case .completed: .green
        case .blocked, .cancelled: .orange
        case .failed: .red
        }
    }
}
