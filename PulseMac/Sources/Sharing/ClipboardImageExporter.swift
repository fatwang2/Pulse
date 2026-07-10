import AppKit

/// The only AppKit boundary in the initial sharing flow: write encoded image types to the system pasteboard.
@MainActor
enum ClipboardImageExporter {
    static func write(_ artifact: ShareImageArtifact, to pasteboard: NSPasteboard = .general) throws {
        let item = NSPasteboardItem()
        item.setData(artifact.pngData, forType: .png)
        if let tiffData = artifact.tiffData {
            item.setData(tiffData, forType: .tiff)
        }

        pasteboard.clearContents()
        guard pasteboard.writeObjects([item]) else {
            throw ShareImageError.clipboardWriteFailed
        }
    }
}
