import AppKit

/// Narrow AppKit boundary for reading text the user copied for import.
/// Mirrors `ClipboardTextExporter` so both directions cross AppKit in one place.
@MainActor
enum ClipboardTextReader {
    static func read(from pasteboard: NSPasteboard = .general) -> String? {
        guard let text = pasteboard.string(forType: .string) else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
