import AppKit

enum ClipboardTextError: LocalizedError {
    case writeFailed

    var errorDescription: String? {
        "The text could not be copied to the clipboard."
    }
}

/// Narrow AppKit boundary for putting a market text snapshot on the macOS pasteboard.
@MainActor
enum ClipboardTextExporter {
    static func write(_ text: String, to pasteboard: NSPasteboard = .general) throws {
        let item = NSPasteboardItem()
        guard item.setString(text, forType: .string) else {
            throw ClipboardTextError.writeFailed
        }

        pasteboard.clearContents()
        guard pasteboard.writeObjects([item]) else {
            throw ClipboardTextError.writeFailed
        }
    }
}
