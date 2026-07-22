import Foundation

@MainActor
enum SessionRecencyLabel {
    private static let formatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    static func text(for date: Date) -> String {
        guard date != .distantPast else { return "Unknown" }
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
