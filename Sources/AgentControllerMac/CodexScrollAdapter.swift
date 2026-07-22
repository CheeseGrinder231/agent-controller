import AgentControllerCore
import AppKit
import ApplicationServices
import Foundation

public enum CodexScrollError: Error, Equatable, Sendable {
    case accessibilityPermissionRequired
    case unsupportedApplication
    case focusChanged
    case windowUnavailable
    case eventCreationFailed
}

struct CodexScrollTarget: Equatable {
    let windowID: CGWindowID
    let point: CGPoint
}

@MainActor
public final class CodexScrollAdapter {
    static let maximumEventDelta: Int32 = 10

    private let trustCheck: () -> Bool
    private let currentContext: () -> ApplicationContext?
    private let targetWindow: (_ processIdentifier: Int32) -> CodexScrollTarget?
    private let validateTarget: (
        _ processIdentifier: Int32,
        _ target: CodexScrollTarget
    ) -> Bool
    private let postScroll: (_ point: CGPoint, _ delta: Int32) -> Bool

    public convenience init() {
        self.init(
            trustCheck: { AXIsProcessTrusted() },
            currentContext: {
                guard let application = NSWorkspace.shared.frontmostApplication,
                      let bundleIdentifier = application.bundleIdentifier else { return nil }
                return ApplicationContext(
                    processIdentifier: application.processIdentifier,
                    bundleIdentifier: bundleIdentifier,
                    displayName: application.localizedName ?? bundleIdentifier
                )
            },
            targetWindow: { processIdentifier in
                Self.frontmostWindowTarget(processIdentifier: processIdentifier)
            },
            validateTarget: { processIdentifier, target in
                Self.windowTargetIsValid(target, processIdentifier: processIdentifier)
            },
            postScroll: { point, delta in
                guard let source = CGEventSource(stateID: .hidSystemState),
                      let event = CGEvent(
                        scrollWheelEvent2Source: source,
                        units: .pixel,
                        wheelCount: 1,
                        wheel1: delta,
                        wheel2: 0,
                        wheel3: 0
                      ) else { return false }
                event.location = point
                event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
                event.post(tap: .cghidEventTap)
                return true
            }
        )
    }

    init(
        trustCheck: @escaping () -> Bool,
        currentContext: @escaping () -> ApplicationContext?,
        targetWindow: @escaping (_ processIdentifier: Int32) -> CodexScrollTarget?,
        validateTarget: @escaping (
            _ processIdentifier: Int32,
            _ target: CodexScrollTarget
        ) -> Bool,
        postScroll: @escaping (_ point: CGPoint, _ delta: Int32) -> Bool
    ) {
        self.trustCheck = trustCheck
        self.currentContext = currentContext
        self.targetWindow = targetWindow
        self.validateTarget = validateTarget
        self.postScroll = postScroll
    }

    public func scroll(delta: Int32, frozenContext: ApplicationContext) throws {
        guard delta != 0 else { return }
        guard frozenContext.bundleIdentifier == ProfileRegistry.codexBundleIdentifier else {
            throw CodexScrollError.unsupportedApplication
        }
        guard currentContext() == frozenContext else { throw CodexScrollError.focusChanged }
        guard trustCheck() else { throw CodexScrollError.accessibilityPermissionRequired }

        var remaining = delta
        while remaining != 0 {
            guard currentContext() == frozenContext else { throw CodexScrollError.focusChanged }
            guard let target = targetWindow(frozenContext.processIdentifier) else {
                throw CodexScrollError.windowUnavailable
            }
            guard currentContext() == frozenContext,
                  let currentTarget = targetWindow(frozenContext.processIdentifier),
                  currentTarget.windowID == target.windowID,
                  validateTarget(frozenContext.processIdentifier, currentTarget),
                  currentContext() == frozenContext else {
                throw CodexScrollError.focusChanged
            }
            let chunk = min(max(remaining, -Self.maximumEventDelta), Self.maximumEventDelta)
            guard postScroll(currentTarget.point, chunk) else {
                throw CodexScrollError.eventCreationFailed
            }
            remaining -= chunk
        }
    }

    nonisolated static func frontmostWindowTarget(
        processIdentifier: Int32
    ) -> CodexScrollTarget? {
        guard let window = CodexWindowResolver.frontmost(
            processIdentifier: processIdentifier
        ) else { return nil }
        // Codex's transcript sits between the left navigation and bottom composer.
        // This point stays within that region across the supported compact and wide layouts.
        return CodexScrollTarget(
            windowID: window.windowID,
            point: CGPoint(
                x: window.bounds.minX + window.bounds.width * 0.46,
                y: window.bounds.minY + window.bounds.height * 0.42
            )
        )
    }

    nonisolated static func windowTargetIsValid(
        _ target: CodexScrollTarget,
        processIdentifier: Int32
    ) -> Bool {
        guard target.windowID != kCGNullWindowID,
              let windows = CGWindowListCopyWindowInfo(
                [.optionIncludingWindow, .excludeDesktopElements],
                target.windowID
              ) as? [[String: Any]],
              let window = windows.first,
              (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value
                == processIdentifier,
              (window[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
              (window[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 0 > 0,
              let boundsDictionary = window[kCGWindowBounds as String] as? NSDictionary,
              let bounds = CGRect(dictionaryRepresentation: boundsDictionary),
              bounds.contains(target.point) else { return false }
        return true
    }
}
