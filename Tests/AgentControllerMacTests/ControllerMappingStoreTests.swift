import Foundation
import Testing
@testable import AgentControllerMac

@Test func mappingStoreCreatesStructuredDefaultsAndPreservesLegacyKey() throws {
    let (defaults, store) = makeMappingStore()
    defer { defaults.removePersistentDomain(forName: defaultsSuite(defaults)) }

    let settings = store.load()

    #expect(settings.globalEnter == .defaultReturn)
    #expect(settings.globalTab == .defaultTab)
    #expect(settings.codexDictation == .defaultDictation)
    #expect(settings.codexStop == nil)
    #expect(settings.codexScroll == .default)
    #expect(defaults.data(forKey: ControllerMappingStore.storageKey) != nil)
    #expect(defaults.string(forKey: ControllerMappingStore.legacyDictationKey) == nil)
}

@Test func mappingStoreMigratesValidAndInvalidLegacyDictationOnce() {
    let (validDefaults, validStore) = makeMappingStore()
    defer { validDefaults.removePersistentDomain(forName: defaultsSuite(validDefaults)) }
    validDefaults.set("Control+Shift+V", forKey: ControllerMappingStore.legacyDictationKey)
    #expect(validStore.load().codexDictation?.displayName == "Control+Shift+V")

    let (invalidDefaults, invalidStore) = makeMappingStore()
    defer { invalidDefaults.removePersistentDomain(forName: defaultsSuite(invalidDefaults)) }
    invalidDefaults.set("D", forKey: ControllerMappingStore.legacyDictationKey)
    #expect(invalidStore.load().codexDictation == nil)
    #expect(invalidDefaults.string(forKey: ControllerMappingStore.legacyDictationKey) == "D")
}

@Test func structuredMappingWinsAfterMigrationAndRoundTrips() {
    let (defaults, store) = makeMappingStore()
    defer { defaults.removePersistentDomain(forName: defaultsSuite(defaults)) }
    defaults.set("Control+Shift+V", forKey: ControllerMappingStore.legacyDictationKey)
    var settings = store.load()
    settings.set(.defaultEscape, for: .codexStop)
    store.save(settings)
    defaults.set("Command+Shift+P", forKey: ControllerMappingStore.legacyDictationKey)

    let reloaded = store.load()
    #expect(reloaded.codexDictation?.displayName == "Control+Shift+V")
    #expect(reloaded.codexStop == .defaultEscape)
}

@Test func collisionDetectionIncludesHeldCommandComposition() {
    let settings = ControllerMappingSettings()
    let commandReturn = KeyboardChord.defaultReturn.withAdditionalModifier(.command)

    #expect(settings.conflictingAction(for: .defaultTab, action: .globalEnter) == .globalTab)
    #expect(settings.conflictingAction(for: commandReturn, action: .codexStop) == .globalEnter)
    #expect(settings.conflictingAction(for: .defaultEscape, action: .codexStop) == nil)
}

@Test func resetCandidateStillDetectsAUserCreatedCollision() {
    var settings = ControllerMappingSettings()
    settings.set(.defaultEscape, for: .globalTab)
    settings.set(.defaultTab, for: .codexStop)

    #expect(settings.conflictingAction(for: .defaultTab, action: .globalTab) == .codexStop)
}

private func makeMappingStore() -> (UserDefaults, ControllerMappingStore) {
    let suite = "AgentControllerTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.set(suite, forKey: "testSuiteName")
    return (defaults, ControllerMappingStore(defaults: defaults))
}

private func defaultsSuite(_ defaults: UserDefaults) -> String {
    defaults.string(forKey: "testSuiteName")!
}
