import AgentControllerCore
import Foundation

public struct CodexModeShortcutContract: Equatable, Sendable {
    public let semanticAction: String
    public let commandIdentifier: String
    public let targetBundleIdentifier: String
    public let defaultShortcut: KeyboardChord
}

public enum CodexModeShortcutError: Error, Equatable, Sendable {
    case commandDisabled
    case unsupportedShortcut
}

/// Resolves Codex Desktop's app-scoped `switchToMode2` command. Codex mode is
/// the second product mode; its macOS default is Control+2. Reading Codex's
/// own keymap keeps the semantic action working when that shortcut is changed.
public struct CodexModeShortcutResolver {
    public static let contract = CodexModeShortcutContract(
        semanticAction: "activateCodexTaskMode",
        commandIdentifier: "switchToMode2",
        targetBundleIdentifier: ProfileRegistry.codexBundleIdentifier,
        defaultShortcut: .defaultCodexMode
    )

    private struct Binding: Decodable {
        let command: String
        let key: String?
    }

    private let loadKeymap: () -> Data?

    public init(
        keymapURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: ".codex/keybindings.json")
    ) {
        loadKeymap = { try? Data(contentsOf: keymapURL, options: [.mappedIfSafe]) }
    }

    init(loadKeymap: @escaping () -> Data?) {
        self.loadKeymap = loadKeymap
    }

    public func resolve() throws -> KeyboardChord {
        try Self.resolve(data: loadKeymap())
    }

    static func resolve(data: Data?) throws -> KeyboardChord {
        guard let data,
              let bindings = try? JSONDecoder().decode([Binding].self, from: data) else {
            return contract.defaultShortcut
        }
        let commandBindings = bindings.filter { $0.command == contract.commandIdentifier }
        guard !commandBindings.isEmpty else { return contract.defaultShortcut }
        guard commandBindings.allSatisfy({ $0.key != nil }) else {
            throw CodexModeShortcutError.commandDisabled
        }
        for binding in commandBindings {
            guard let key = binding.key else { continue }
            let macAccelerator = key.replacingOccurrences(of: "CmdOrCtrl", with: "Command")
            if let chord = KeyboardChord(
                legacyDescription: macAccelerator,
                triggerMode: .pulse,
                requiresModifier: false
            ) {
                return chord
            }
        }
        throw CodexModeShortcutError.unsupportedShortcut
    }
}
