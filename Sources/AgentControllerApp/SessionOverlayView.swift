import AgentControllerCore
import SwiftUI

struct SessionOverlayView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if activeItemCount == 0 {
                emptyState
            } else if model.selectorMode == .sessionPicker {
                ScrollViewReader { proxy in
                    ScrollView(.vertical) {
                        VStack(spacing: 6) {
                            ForEach(Array(model.selectorSessions.enumerated()), id: \.element.id) { index, session in
                                SessionChoice(session: session, selected: model.selectedIndex == index)
                                    .id(session.id)
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                    .onChange(of: model.selectedIndex) { _, selectedIndex in
                        guard let selectedIndex,
                              model.selectorSessions.indices.contains(selectedIndex) else { return }
                        withAnimation(.easeOut(duration: 0.12)) {
                            proxy.scrollTo(model.selectorSessions[selectedIndex].id, anchor: .center)
                        }
                    }
                }
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.vertical) {
                        VStack(spacing: 6) {
                            ForEach(Array(model.selectorProjects.enumerated()), id: \.element.id) { index, project in
                                ProjectChoice(
                                    project: project,
                                    selected: model.selectedIndex == index,
                                    commitEnabled: !model.isPreviewOnly
                                )
                                    .id(project.id)
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                    .onChange(of: model.selectedIndex) { _, selectedIndex in
                        guard let selectedIndex,
                              model.selectorProjects.indices.contains(selectedIndex) else { return }
                        withAnimation(.easeOut(duration: 0.12)) {
                            proxy.scrollTo(model.selectorProjects[selectedIndex].id, anchor: .center)
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.98))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.2), radius: 20, y: 9)
        .padding(12)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: model.isPreviewOnly ? "eye" : selectorIcon)
                .foregroundStyle(.secondary)
            Text(headerTitle)
                .font(.callout.weight(.semibold))
            Spacer()
            Text(instruction)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var emptyState: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
                .opacity(activeInventoryState == .loading ? 1 : 0)
            VStack(alignment: .leading, spacing: 2) {
                Text(emptyTitle)
                    .font(.callout.weight(.medium))
                Text(emptyDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .background(Color.primary.opacity(0.055))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var instruction: String {
        if model.isPreviewOnly {
            return model.selectorMode == .projectStarter
                ? "Visual only · no session starts"
                : "Visual only · no session opens"
        }
        if model.selectedIndex == nil { return "D-pad / left stick · B cancel" }
        return model.selectorMode == .projectStarter ? "Release L3 to start" : "Release LB to open"
    }

    private var emptyTitle: String {
        switch activeInventoryState {
        case .loading:
            model.selectorMode == .projectStarter ? "Loading recent projects…" : "Loading recent chats…"
        case .unavailable:
            model.selectorMode == .projectStarter ? "Codex projects unavailable" : "Codex sessions unavailable"
        default:
            model.selectorMode == .projectStarter ? "No recent local projects" : "No recent local chats"
        }
    }

    private var emptyDetail: String {
        switch activeInventoryState {
        case .unavailable:
            "Open Codex and refresh from the control center."
        default:
            model.selectorMode == .projectStarter
                ? "Open a project in Codex once, then refresh."
                : "The picker stays closed until a real session is available."
        }
    }

    private var activeItemCount: Int {
        switch model.selectorMode {
        case .sessionPicker: model.selectorSessions.count
        case .projectStarter: model.selectorProjects.count
        }
    }

    private var activeInventoryState: SessionInventoryState {
        switch model.selectorMode {
        case .sessionPicker: model.inventoryState
        case .projectStarter: model.projectInventoryState
        }
    }

    private var selectorIcon: String {
        model.selectorMode == .projectStarter ? "folder.badge.plus" : "rectangle.stack.fill"
    }

    private var headerTitle: String {
        if model.isPreviewOnly {
            return model.selectorMode == .projectStarter
                ? "Session Starter preview"
                : "Session picker preview"
        }
        return model.selectorMode == .projectStarter ? "Start in a project" : "Recent Codex chats"
    }
}

private struct SessionChoice: View {
    let session: CodexSessionSummary
    let selected: Bool

    var body: some View {
        HStack(spacing: 11) {
            Circle()
                .fill(statusColor)
                .frame(width: 7, height: 7)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(session.title)
                    .font(.callout.weight(selected ? .semibold : .medium))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(session.project)
                        .lineLimit(1)
                    Text("·")
                    Text(SessionRecencyLabel.text(for: session.updatedAt))
                    if statusLabel != "Recent" {
                        Text("·")
                        Text(statusLabel)
                    }
                }
                .font(.caption2)
                .foregroundStyle(selected ? Color.white.opacity(0.82) : Color.secondary)
            }
            Spacer(minLength: 8)
            if selected {
                Image(systemName: "arrow.turn.down.left")
                    .font(.caption.weight(.semibold))
                    .accessibilityLabel("Release LB to open")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .foregroundStyle(selected ? Color.white : Color.primary)
        .background(selected ? Color.accentColor : Color.primary.opacity(0.055))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(selected ? Color.clear : Color.primary.opacity(0.08), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var statusColor: Color {
        switch session.status {
        case .active(let needsAttention):
            needsAttention ? .orange : .green
        case .idle:
            .green
        case .error:
            .red
        case .notLoaded:
            .secondary
        }
    }

    private var statusLabel: String {
        switch session.status {
        case .active(let needsAttention):
            needsAttention ? "Needs input" : "Running"
        case .idle:
            "Idle"
        case .error:
            "Error"
        case .notLoaded:
            "Recent"
        }
    }
}

private struct ProjectChoice: View {
    let project: CodexProjectSummary
    let selected: Bool
    let commitEnabled: Bool

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: "folder.fill")
                .font(.caption)
                .foregroundStyle(selected ? Color.white.opacity(0.9) : Color.accentColor)
                .frame(width: 12)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(project.name)
                    .font(.callout.weight(selected ? .semibold : .medium))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(project.path)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text("·")
                    Text(SessionRecencyLabel.text(for: project.lastUsedAt))
                        .fixedSize()
                }
                .font(.caption2)
                .foregroundStyle(selected ? Color.white.opacity(0.82) : Color.secondary)
            }
            Spacer(minLength: 8)
            if selected {
                Image(systemName: commitEnabled ? "plus" : "checkmark")
                    .font(.caption.weight(.semibold))
                    .accessibilityLabel(commitEnabled ? "Release L3 to start" : "Selected project preview")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .foregroundStyle(selected ? Color.white : Color.primary)
        .background(selected ? Color.accentColor : Color.primary.opacity(0.055))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(selected ? Color.clear : Color.primary.opacity(0.08), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
