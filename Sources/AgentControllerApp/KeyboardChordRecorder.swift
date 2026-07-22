import AgentControllerMac
import AppKit
import Foundation

@MainActor
final class KeyboardChordRecorder {
    enum CancellationReason {
        case user
        case focusLost
        case timedOut
        case invalidKey
        case multipleKeys
    }

    var isRecording: Bool { eventMonitor != nil }

    private var eventMonitor: Any?
    private var focusObservers: [NSObjectProtocol] = []
    private var timeoutTask: Task<Void, Never>?
    private var candidate: KeyboardChord?
    private var candidateKeyIsDown = false
    private var currentModifiers = Set<KeyboardChord.Modifier>()
    private var completion: ((KeyboardChord) -> Void)?
    private var cancellation: ((CancellationReason) -> Void)?

    func begin(
        triggerMode: KeyboardChord.TriggerMode,
        completion: @escaping (KeyboardChord) -> Void,
        cancellation: @escaping (CancellationReason) -> Void
    ) {
        cancel(notify: false, reason: .user)
        self.completion = completion
        self.cancellation = cancellation

        eventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .keyUp, .flagsChanged]
        ) { [weak self] event in
            guard let self else { return event }
            self.handle(event, triggerMode: triggerMode)
            return nil
        }

        let center = NotificationCenter.default
        focusObservers = [
            center.addObserver(
                forName: NSApplication.didResignActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.cancel(reason: .focusLost) }
            },
            center.addObserver(
                forName: NSWindow.didResignKeyNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.cancel(reason: .focusLost) }
            },
        ]

        timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(15))
            guard !Task.isCancelled else { return }
            self?.cancel(reason: .timedOut)
        }
    }

    func cancel(reason: CancellationReason = .user) {
        cancel(notify: true, reason: reason)
    }

    private func handle(_ event: NSEvent, triggerMode: KeyboardChord.TriggerMode) {
        currentModifiers = modifiers(from: event.modifierFlags)
        switch event.type {
        case .keyDown:
            guard !event.isARepeat else { return }
            guard candidate == nil else {
                cancel(reason: .multipleKeys)
                return
            }
            guard let key = KeyboardChord.key(
                keyCode: event.keyCode,
                characters: event.charactersIgnoringModifiers
            ) else {
                cancel(reason: .invalidKey)
                return
            }
            candidate = KeyboardChord(
                modifiers: Array(currentModifiers),
                key: key,
                triggerMode: triggerMode
            )
            candidateKeyIsDown = true
        case .keyUp:
            guard event.keyCode == candidate?.key.keyCode else { return }
            candidateKeyIsDown = false
            completeIfReleased()
        case .flagsChanged:
            completeIfReleased()
        default:
            break
        }
    }

    private func completeIfReleased() {
        guard let candidate,
              !candidateKeyIsDown,
              currentModifiers.isDisjoint(with: candidate.modifiers) else { return }
        let completion = self.completion
        cancel(notify: false, reason: .user)
        completion?(candidate)
    }

    private func cancel(notify: Bool, reason: CancellationReason) {
        let cancellation = self.cancellation
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        eventMonitor = nil
        focusObservers.forEach(NotificationCenter.default.removeObserver)
        focusObservers = []
        timeoutTask?.cancel()
        timeoutTask = nil
        candidate = nil
        candidateKeyIsDown = false
        currentModifiers = []
        completion = nil
        self.cancellation = nil
        if notify { cancellation?(reason) }
    }

    private func modifiers(from flags: NSEvent.ModifierFlags) -> Set<KeyboardChord.Modifier> {
        var result = Set<KeyboardChord.Modifier>()
        if flags.contains(.control) { result.insert(.control) }
        if flags.contains(.option) { result.insert(.option) }
        if flags.contains(.shift) { result.insert(.shift) }
        if flags.contains(.command) { result.insert(.command) }
        return result
    }
}
