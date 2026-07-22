import SwiftUI

@main
struct AgentControllerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel.shared

    var body: some Scene {
        WindowGroup("Agent Controller", id: "control-center") {
            ControlCenterView(model: model)
        }
        .defaultSize(width: 820, height: 560)
        .windowResizability(.contentMinSize)

        MenuBarExtra {
            ControllerMenuView(model: model)
        } label: {
            Label(
                model.isArmed ? "Agent Controller enabled" : "Agent Controller paused",
                systemImage: model.isArmed ? "gamecontroller.fill" : "gamecontroller"
            )
        }
    }
}

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate {
    private var overlayPanelController: OverlayPanelController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let model = AppModel.shared
        overlayPanelController = OverlayPanelController(model: model)
        model.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppModel.shared.stop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

private struct ControllerMenuView: View {
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Open Control Center") {
            openWindow(id: "control-center")
            NSApp.activate(ignoringOtherApps: true)
        }
        Divider()
        Toggle("Controller Enabled", isOn: $model.isArmed)
        Text(model.controllerName ?? "No controller connected")
        Text(model.isCodexFrontmost ? "Codex frontmost" : "Codex controls waiting")
        Text(model.isDictating ? "RB dictation active" : "Hold RB to dictate")
        Divider()
        Button("Quit Agent Controller") { NSApp.terminate(nil) }
    }
}
