import AgentControllerCore
import AppKit
import Foundation

@MainActor
public final class FrontmostApplicationMonitor {
    public var onChange: ((ApplicationContext?) -> Void)?

    private var activationObserver: NSObjectProtocol?

    public init() {}

    public func stop() {
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        }
        activationObserver = nil
    }

    public func start() {
        if activationObserver == nil {
            activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.publishCurrentContext()
                }
            }
        }
        publishCurrentContext()
    }

    public func currentContext() -> ApplicationContext? {
        guard let application = NSWorkspace.shared.frontmostApplication,
              application.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              let bundleIdentifier = application.bundleIdentifier else {
            return nil
        }
        return ApplicationContext(
            processIdentifier: application.processIdentifier,
            bundleIdentifier: bundleIdentifier,
            displayName: application.localizedName ?? bundleIdentifier
        )
    }

    private func publishCurrentContext() {
        onChange?(currentContext())
    }
}
