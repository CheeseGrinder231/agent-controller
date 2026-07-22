import AgentControllerCore
import Foundation

public enum ControllerMappingAction: String, CaseIterable, Codable, Sendable {
    case globalTab
    case globalEnter
    case codexDictation
    case codexStop

    public var displayName: String {
        switch self {
        case .globalTab: "RT · Tab"
        case .globalEnter: "A · Enter"
        case .codexDictation: "RB · Push to Talk"
        case .codexStop: "X · Stop"
        }
    }

    public var triggerMode: KeyboardChord.TriggerMode {
        self == .codexDictation ? .hold : .pulse
    }
}

public struct ControllerMappingSettings: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public var globalTab: KeyboardChord
    public var globalEnter: KeyboardChord
    public var codexDictation: KeyboardChord?
    public var codexStop: KeyboardChord?
    public var codexScroll: AnalogScrollConfiguration

    public init(
        schemaVersion: Int = 1,
        globalTab: KeyboardChord = .defaultTab,
        globalEnter: KeyboardChord = .defaultReturn,
        codexDictation: KeyboardChord? = .defaultDictation,
        codexStop: KeyboardChord? = nil,
        codexScroll: AnalogScrollConfiguration = .default
    ) {
        self.schemaVersion = schemaVersion
        self.globalTab = globalTab.withTriggerMode(.pulse)
        self.globalEnter = globalEnter.withTriggerMode(.pulse)
        self.codexDictation = codexDictation?.withTriggerMode(.hold)
        self.codexStop = codexStop?.withTriggerMode(.pulse)
        self.codexScroll = codexScroll
    }

    public func chord(for action: ControllerMappingAction) -> KeyboardChord? {
        switch action {
        case .globalTab: globalTab
        case .globalEnter: globalEnter
        case .codexDictation: codexDictation
        case .codexStop: codexStop
        }
    }

    public mutating func set(_ chord: KeyboardChord?, for action: ControllerMappingAction) {
        switch action {
        case .globalTab:
            if let chord { globalTab = chord.withTriggerMode(.pulse) }
        case .globalEnter:
            if let chord { globalEnter = chord.withTriggerMode(.pulse) }
        case .codexDictation:
            codexDictation = chord?.withTriggerMode(.hold)
        case .codexStop:
            codexStop = chord?.withTriggerMode(.pulse)
        }
    }

    public func conflictingAction(
        for candidate: KeyboardChord,
        action: ControllerMappingAction
    ) -> ControllerMappingAction? {
        let candidateVariants = variants(for: candidate, action: action)
        return ControllerMappingAction.allCases.first { other in
            guard other != action, let otherChord = chord(for: other) else { return false }
            return !candidateVariants.isDisjoint(with: variants(for: otherChord, action: other))
        }
    }

    private func variants(
        for chord: KeyboardChord,
        action: ControllerMappingAction
    ) -> Set<KeyboardChord> {
        let canonical = chord.withTriggerMode(.pulse)
        guard action == .globalTab || action == .globalEnter else { return [canonical] }
        return [canonical, canonical.withAdditionalModifier(.command)]
    }
}

public final class ControllerMappingStore: @unchecked Sendable {
    public static let storageKey = "controllerMappings.v1"
    public static let legacyDictationKey = "codexDictationShortcut"

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> ControllerMappingSettings {
        if let data = defaults.data(forKey: Self.storageKey),
           let decoded = try? decoder.decode(ControllerMappingSettings.self, from: data),
           decoded.schemaVersion == 1 {
            return decoded
        }

        let dictation: KeyboardChord?
        if let legacy = defaults.string(forKey: Self.legacyDictationKey) {
            dictation = KeyboardChord(
                legacyDescription: legacy,
                triggerMode: .hold,
                requiresModifier: true
            )
        } else {
            dictation = .defaultDictation
        }
        let migrated = ControllerMappingSettings(codexDictation: dictation)
        save(migrated)
        return migrated
    }

    public func save(_ settings: ControllerMappingSettings) {
        guard let data = try? encoder.encode(settings) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
