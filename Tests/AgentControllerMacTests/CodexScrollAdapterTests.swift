import AgentControllerCore
import CoreGraphics
import Testing
@testable import AgentControllerMac

@MainActor
@Test func scrollPostsToTheFrozenCodexWindowInBoundedChunks() throws {
    let codex = scrollCodex()
    var frontmost = codex
    let point = CGPoint(x: 640, y: 360)
    var targetPIDs: [Int32] = []
    var posts: [(CGPoint, Int32)] = []
    let adapter = CodexScrollAdapter(
        trustCheck: { true },
        currentContext: { frontmost },
        targetWindow: {
            targetPIDs.append($0)
            return CodexScrollTarget(windowID: 7, point: point)
        },
        validateTarget: { _, _ in true },
        postScroll: {
            posts.append(($0, $1))
            return true
        }
    )

    try adapter.scroll(delta: 24, frozenContext: codex)
    #expect(targetPIDs == [42, 42, 42, 42, 42, 42])
    #expect(posts.map(\.0) == [point, point, point])
    #expect(posts.map(\.1) == [10, 10, 4])

    frontmost = ApplicationContext(
        processIdentifier: 99,
        bundleIdentifier: "com.apple.Terminal",
        displayName: "Terminal"
    )
    #expect(throws: CodexScrollError.focusChanged) {
        try adapter.scroll(delta: 12, frozenContext: codex)
    }
    #expect(posts.count == 3)
}

@MainActor
@Test func scrollFailsClosedBeforePostingWithoutAccessibility() {
    let codex = scrollCodex()
    var posted = false
    let adapter = CodexScrollAdapter(
        trustCheck: { false },
        currentContext: { codex },
        targetWindow: { _ in scrollTarget() },
        validateTarget: { _, _ in true },
        postScroll: { _, _ in
            posted = true
            return true
        }
    )

    #expect(throws: CodexScrollError.accessibilityPermissionRequired) {
        try adapter.scroll(delta: 8, frozenContext: codex)
    }
    #expect(!posted)
}

@MainActor
@Test func scrollFailsClosedWithoutAFrontmostCodexWindow() {
    let codex = scrollCodex()
    var posted = false
    let adapter = CodexScrollAdapter(
        trustCheck: { true },
        currentContext: { codex },
        targetWindow: { _ in nil },
        validateTarget: { _, _ in true },
        postScroll: { _, _ in
            posted = true
            return true
        }
    )

    #expect(throws: CodexScrollError.windowUnavailable) {
        try adapter.scroll(delta: 8, frozenContext: codex)
    }
    #expect(!posted)
}

@MainActor
@Test func scrollRevalidatesFocusBeforeEveryChunk() {
    let codex = scrollCodex()
    var frontmost: ApplicationContext? = codex
    var posts: [Int32] = []
    let adapter = CodexScrollAdapter(
        trustCheck: { true },
        currentContext: { frontmost },
        targetWindow: { _ in scrollTarget() },
        validateTarget: { _, _ in true },
        postScroll: { _, delta in
            posts.append(delta)
            frontmost = ApplicationContext(
                processIdentifier: 99,
                bundleIdentifier: "com.apple.Safari",
                displayName: "Safari"
            )
            return true
        }
    )

    #expect(throws: CodexScrollError.focusChanged) {
        try adapter.scroll(delta: 18, frozenContext: codex)
    }
    #expect(posts == [10])
}

@MainActor
@Test func scrollRevalidatesFocusAfterResolvingTheWindow() {
    let codex = scrollCodex()
    var frontmost: ApplicationContext? = codex
    var posted = false
    let adapter = CodexScrollAdapter(
        trustCheck: { true },
        currentContext: { frontmost },
        targetWindow: { _ in
            frontmost = ApplicationContext(
                processIdentifier: 99,
                bundleIdentifier: "com.apple.Safari",
                displayName: "Safari"
            )
            return scrollTarget()
        },
        validateTarget: { _, _ in true },
        postScroll: { _, _ in
            posted = true
            return true
        }
    )

    #expect(throws: CodexScrollError.focusChanged) {
        try adapter.scroll(delta: 8, frozenContext: codex)
    }
    #expect(!posted)
}

@MainActor
@Test func scrollFailsClosedWhenTheFrontmostCodexWindowChanges() {
    let codex = scrollCodex()
    var resolutionCount = 0
    var posted = false
    let adapter = CodexScrollAdapter(
        trustCheck: { true },
        currentContext: { codex },
        targetWindow: { _ in
            resolutionCount += 1
            return CodexScrollTarget(
                windowID: resolutionCount == 1 ? 7 : 8,
                point: CGPoint(x: 640, y: 360)
            )
        },
        validateTarget: { _, _ in true },
        postScroll: { _, _ in
            posted = true
            return true
        }
    )

    #expect(throws: CodexScrollError.focusChanged) {
        try adapter.scroll(delta: 8, frozenContext: codex)
    }
    #expect(!posted)
}

private func scrollCodex() -> ApplicationContext {
    ApplicationContext(
        processIdentifier: 42,
        bundleIdentifier: ProfileRegistry.codexBundleIdentifier,
        displayName: "Codex"
    )
}

private func scrollTarget() -> CodexScrollTarget {
    CodexScrollTarget(windowID: 7, point: CGPoint(x: 640, y: 360))
}
