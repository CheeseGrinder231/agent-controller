import CoreGraphics
import Foundation

struct CodexWindowIdentity: Equatable {
    let windowID: CGWindowID
    let bounds: CGRect
}

enum CodexWindowResolver {
    static func frontmost(processIdentifier: Int32) -> CodexWindowIdentity? {
        guard let windows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else { return nil }

        for window in windows {
            guard (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value
                    == processIdentifier,
                  (window[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  (window[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 0 > 0,
                  let windowID = (window[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                  let boundsDictionary = window[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDictionary),
                  bounds.width >= 480,
                  bounds.height >= 320 else { continue }
            return CodexWindowIdentity(windowID: windowID, bounds: bounds)
        }
        return nil
    }

    static func isFrontmost(
        _ target: CodexWindowIdentity,
        processIdentifier: Int32
    ) -> Bool {
        guard let current = frontmost(processIdentifier: processIdentifier),
              current.windowID == target.windowID else { return false }
        return true
    }
}
