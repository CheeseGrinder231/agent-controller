import AgentControllerMac
import SwiftUI

struct SettingsPageHeader: View {
    let icon: String
    let title: String
    let subtitle: String
    var status: String?
    var statusColor: Color = .secondary

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 38, height: 38)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.title.weight(.semibold))
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let status {
                Text(status)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(statusColor)
                    .padding(.top, 7)
            }
        }
        .padding(.horizontal, 26)
        .padding(.top, 24)
        .padding(.bottom, 8)
    }
}

struct ControllerInputBadge: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.caption.monospaced().weight(.semibold))
            .foregroundStyle(.primary)
            .frame(minWidth: 28)
            .padding(.horizontal, 5)
            .padding(.vertical, 3)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
            .accessibilityLabel("Controller input \(label)")
    }
}

struct KeyboardChordKeycaps: View {
    let chord: KeyboardChord?

    var body: some View {
        if let chord {
            HStack(spacing: 4) {
                ForEach(Array(chord.keycapLabels.enumerated()), id: \.offset) { _, label in
                    Text(label)
                        .font(.caption.monospaced().weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(chord.displayName)
        } else {
            Text("Not configured")
                .font(.caption.weight(.medium))
                .foregroundStyle(.orange)
        }
    }
}

struct KeyboardMappingRow: View {
    let input: String
    let title: String
    let detail: String
    let action: ControllerMappingAction
    let chord: KeyboardChord?
    @ObservedObject var model: AppModel
    let select: () -> Void

    var body: some View {
        HStack(spacing: 11) {
            ControllerInputBadge(label: input)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                select()
                model.beginMappingRecording(action)
            } label: {
                KeyboardChordKeycaps(chord: chord)
            }
            .buttonStyle(.plain)
            .disabled(model.hasPendingKeyRelease || model.isRecordingBinding)
            .help("Click, then press the keyboard chord you want")
        }
        .padding(.vertical, 3)
    }
}

struct KeyboardBindingCapturePanel: View {
    let action: ControllerMappingAction
    let currentChord: KeyboardChord?
    @ObservedObject var model: AppModel
    var sectionTitle: String? = nil

    var body: some View {
        Section(sectionTitle ?? "Edit \(action.displayName)") {
            LabeledContent("Current") {
                KeyboardChordKeycaps(chord: currentChord)
            }

            if model.editingMapping == action {
                if model.isRecordingBinding {
                    HStack(spacing: 9) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Press one keyboard chord, then release every key.")
                            .foregroundStyle(.secondary)
                    }
                } else if let staged = model.stagedMappingChord {
                    LabeledContent("Captured") {
                        KeyboardChordKeycaps(chord: staged)
                    }
                }

            } else {
                Text("Click the keycaps above to record a replacement. Nothing changes until Save.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let error = model.mappingError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Button("Record") { model.beginMappingRecording(action) }
                    .disabled(model.isRecordingBinding || model.hasPendingKeyRelease)
                Button("Save") { model.saveStagedMapping() }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.editingMapping != action || model.stagedMappingChord == nil)
                Button("Cancel") { model.cancelMappingRecording() }
                    .disabled(model.editingMapping != action)
                Spacer()
                Button(action == .codexStop ? "Clear" : "Reset Default") {
                    model.resetMapping(action)
                }
                .disabled(model.isRecordingBinding || model.hasPendingKeyRelease)
            }
        }
    }
}

struct MappingSummaryRow: View {
    let input: String
    let title: String
    let detail: String
    let value: String
    let actionLabel: String
    let selected: Bool
    var disabled = false
    let select: () -> Void

    var body: some View {
        HStack(spacing: 11) {
            ControllerInputBadge(label: input)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(value)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if selected {
                Image(systemName: "checkmark")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Selected mapping")
            } else {
                Button(actionLabel, action: select)
                    .disabled(disabled)
            }
        }
        .padding(.vertical, 3)
    }
}

struct GlobalMappingRow: View {
    let input: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 11) {
            ControllerInputBadge(label: input)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("Global")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
    }
}

struct SettingsStatusRow: View {
    let title: String
    let value: String
    var systemImage: String? = nil
    var color: Color = .secondary

    var body: some View {
        LabeledContent {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(value)
            }
            .foregroundStyle(color)
        } label: {
            Text(title)
        }
    }
}
