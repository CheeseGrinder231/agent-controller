import ApplicationServices
import Foundation

public struct CodexKeyboardShortcutSetting: Equatable, Sendable {
    public let draft: String
    public let shortcut: KeyboardChord?

    public var canDispatch: Bool { shortcut != nil }

    public init(saved: String?) {
        self.init(draft: saved ?? KeyboardChord.defaultDictation.displayName)
    }

    public init(draft: String) {
        self.draft = draft
        shortcut = KeyboardChord(
            legacyDescription: draft,
            triggerMode: .hold,
            requiresModifier: true
        )
    }
}

public struct KeyboardChord: Codable, Equatable, Hashable, Sendable {
    public enum TriggerMode: String, Codable, Equatable, Hashable, Sendable {
        case pulse
        case hold
    }

    public enum Modifier: String, CaseIterable, Codable, Hashable, Sendable {
        case control = "Control"
        case option = "Option"
        case shift = "Shift"
        case command = "Command"

        var keyCode: CGKeyCode {
            switch self {
            case .control: 59
            case .option: 58
            case .shift: 56
            case .command: 55
            }
        }

        var eventFlag: CGEventFlags {
            switch self {
            case .control: .maskControl
            case .option: .maskAlternate
            case .shift: .maskShift
            case .command: .maskCommand
            }
        }

        public var symbol: String {
            switch self {
            case .control: "⌃"
            case .option: "⌥"
            case .shift: "⇧"
            case .command: "⌘"
            }
        }
    }

    public struct Key: Codable, Equatable, Hashable, Sendable {
        public let displayName: String
        public let keyCode: CGKeyCode

        public init(displayName: String, keyCode: CGKeyCode) {
            self.displayName = displayName
            self.keyCode = keyCode
        }
    }

    public static let defaultDictation = KeyboardChord(
        modifiers: [.control, .shift],
        key: Key(displayName: "D", keyCode: 2),
        triggerMode: .hold
    )
    public static let defaultReturn = KeyboardChord(
        modifiers: [],
        key: Key(displayName: "Return", keyCode: 36),
        triggerMode: .pulse
    )
    public static let defaultTab = KeyboardChord(
        modifiers: [],
        key: Key(displayName: "Tab", keyCode: 48),
        triggerMode: .pulse
    )
    public static let defaultEscape = KeyboardChord(
        modifiers: [],
        key: Key(displayName: "Escape", keyCode: 53),
        triggerMode: .pulse
    )
    public static let defaultCodexMode = KeyboardChord(
        modifiers: [.control],
        key: Key(displayName: "2", keyCode: 19),
        triggerMode: .pulse
    )

    public let modifiers: [Modifier]
    public let key: Key
    public let triggerMode: TriggerMode

    public var displayName: String {
        (modifiers.map(\.rawValue) + [key.displayName]).joined(separator: "+")
    }

    public var keycapLabels: [String] {
        modifiers.map(\.symbol) + [Self.keycapLabel(for: key.displayName)]
    }

    public init(modifiers: [Modifier], key: Key, triggerMode: TriggerMode) {
        let unique = Set(modifiers)
        self.modifiers = Modifier.allCases.filter(unique.contains)
        self.key = key
        self.triggerMode = triggerMode
    }

    public init?(description: String) {
        self.init(
            legacyDescription: description,
            triggerMode: .hold,
            requiresModifier: true
        )
    }

    public init?(
        legacyDescription description: String,
        triggerMode: TriggerMode,
        requiresModifier: Bool
    ) {
        let tokens = description.split(separator: "+").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let keyToken = tokens.last,
              let key = Self.namedKeys[keyToken.uppercased()] else { return nil }

        var parsed = Set<Modifier>()
        for token in tokens.dropLast() {
            guard let modifier = Self.modifier(token), parsed.insert(modifier).inserted else {
                return nil
            }
        }
        guard !requiresModifier || !parsed.isEmpty else { return nil }
        self.init(modifiers: Array(parsed), key: key, triggerMode: triggerMode)
    }

    public func withAdditionalModifier(_ modifier: Modifier) -> KeyboardChord {
        KeyboardChord(modifiers: modifiers + [modifier], key: key, triggerMode: triggerMode)
    }

    public func withTriggerMode(_ triggerMode: TriggerMode) -> KeyboardChord {
        KeyboardChord(modifiers: modifiers, key: key, triggerMode: triggerMode)
    }

    public static func key(keyCode: CGKeyCode, characters: String?) -> Key? {
        if let known = keysByCode[keyCode] { return known }
        guard let characters,
              characters.count == 1,
              let character = characters.uppercased().first,
              character.isLetter || character.isNumber else { return nil }
        return Key(displayName: String(character), keyCode: keyCode)
    }

    private static func modifier(_ token: String) -> Modifier? {
        switch token.lowercased() {
        case "control", "ctrl": .control
        case "option", "alt": .option
        case "shift": .shift
        case "command", "cmd": .command
        default: nil
        }
    }

    private static func keycapLabel(for displayName: String) -> String {
        switch displayName {
        case "Return": "↩"
        case "Tab": "⇥"
        case "Escape": "esc"
        case "Space": "space"
        case "Delete": "⌫"
        case "Up": "↑"
        case "Down": "↓"
        case "Left": "←"
        case "Right": "→"
        default: displayName
        }
    }

    private static let namedKeys: [String: Key] = {
        var result = keysByCode.reduce(into: [String: Key]()) { partial, entry in
            partial[entry.value.displayName.uppercased()] = entry.value
        }
        result["ENTER"] = defaultReturn.key
        result["ESC"] = defaultEscape.key
        return result
    }()

    private static let keysByCode: [CGKeyCode: Key] = [
        0: Key(displayName: "A", keyCode: 0),
        11: Key(displayName: "B", keyCode: 11),
        8: Key(displayName: "C", keyCode: 8),
        2: Key(displayName: "D", keyCode: 2),
        14: Key(displayName: "E", keyCode: 14),
        3: Key(displayName: "F", keyCode: 3),
        5: Key(displayName: "G", keyCode: 5),
        4: Key(displayName: "H", keyCode: 4),
        34: Key(displayName: "I", keyCode: 34),
        38: Key(displayName: "J", keyCode: 38),
        40: Key(displayName: "K", keyCode: 40),
        37: Key(displayName: "L", keyCode: 37),
        46: Key(displayName: "M", keyCode: 46),
        45: Key(displayName: "N", keyCode: 45),
        31: Key(displayName: "O", keyCode: 31),
        35: Key(displayName: "P", keyCode: 35),
        12: Key(displayName: "Q", keyCode: 12),
        15: Key(displayName: "R", keyCode: 15),
        1: Key(displayName: "S", keyCode: 1),
        17: Key(displayName: "T", keyCode: 17),
        32: Key(displayName: "U", keyCode: 32),
        9: Key(displayName: "V", keyCode: 9),
        13: Key(displayName: "W", keyCode: 13),
        7: Key(displayName: "X", keyCode: 7),
        16: Key(displayName: "Y", keyCode: 16),
        6: Key(displayName: "Z", keyCode: 6),
        29: Key(displayName: "0", keyCode: 29),
        18: Key(displayName: "1", keyCode: 18),
        19: Key(displayName: "2", keyCode: 19),
        20: Key(displayName: "3", keyCode: 20),
        21: Key(displayName: "4", keyCode: 21),
        23: Key(displayName: "5", keyCode: 23),
        22: Key(displayName: "6", keyCode: 22),
        26: Key(displayName: "7", keyCode: 26),
        28: Key(displayName: "8", keyCode: 28),
        25: Key(displayName: "9", keyCode: 25),
        36: Key(displayName: "Return", keyCode: 36),
        48: Key(displayName: "Tab", keyCode: 48),
        49: Key(displayName: "Space", keyCode: 49),
        51: Key(displayName: "Delete", keyCode: 51),
        53: Key(displayName: "Escape", keyCode: 53),
        123: Key(displayName: "Left", keyCode: 123),
        124: Key(displayName: "Right", keyCode: 124),
        125: Key(displayName: "Down", keyCode: 125),
        126: Key(displayName: "Up", keyCode: 126),
    ]
}

public typealias CodexKeyboardShortcut = KeyboardChord
