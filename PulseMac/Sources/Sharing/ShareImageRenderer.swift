import AppKit
import SwiftUI

struct ShareImageConfiguration {
    var width: CGFloat = 420
    var height: CGFloat?
    var scale: CGFloat = 2
    var colorScheme: ColorScheme
    var locale: Locale

    /// Watchlist card: 1:1 at the base height, growing taller for long lists.
    static func watchlistSquare(
        height: CGFloat,
        colorScheme: ColorScheme,
        locale: Locale
    ) -> Self {
        Self(
            width: 640,
            height: height,
            scale: 2,
            colorScheme: colorScheme,
            locale: locale
        )
    }

    /// Detail card: 16:9, X's native in-stream ratio.
    static func detailLandscape(colorScheme: ColorScheme, locale: Locale) -> Self {
        Self(
            width: DetailShareSnapshot.imageSize.width,
            height: DetailShareSnapshot.imageSize.height,
            scale: 2,
            colorScheme: colorScheme,
            locale: locale
        )
    }
}

struct ShareImageArtifact {
    let image: NSImage
    let pngData: Data
    let tiffData: Data?
}

enum ShareImageError: LocalizedError {
    case renderingFailed
    case encodingFailed
    case clipboardWriteFailed

    var errorDescription: String? {
        switch self {
        case .renderingFailed:
            "The share image could not be rendered."
        case .encodingFailed:
            "The share image could not be encoded."
        case .clipboardWriteFailed:
            "The share image could not be copied to the clipboard."
        }
    }
}

/// Renders any SwiftUI share surface into a reusable image artifact.
/// Feature-specific share views remain responsible only for their content and data snapshot.
@MainActor
enum ShareImageRenderer {
    static func render<Content: View>(
        _ content: Content,
        configuration: ShareImageConfiguration
    ) throws -> ShareImageArtifact {
        let renderedContent = content
            .environment(\.colorScheme, configuration.colorScheme)
            .environment(\.locale, configuration.locale)
            .modifier(ShareImageFrame(
                width: configuration.width,
                height: configuration.height
            ))

        let renderer = ImageRenderer(content: renderedContent)
        renderer.scale = configuration.scale
        renderer.isOpaque = true

        guard let image = renderer.nsImage else {
            throw ShareImageError.renderingFailed
        }
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw ShareImageError.encodingFailed
        }

        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        bitmap.size = image.size
        guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw ShareImageError.encodingFailed
        }

        return ShareImageArtifact(
            image: image,
            pngData: pngData,
            tiffData: image.tiffRepresentation
        )
    }
}

private struct ShareImageFrame: ViewModifier {
    let width: CGFloat
    let height: CGFloat?

    func body(content: Content) -> some View {
        if let height {
            content.frame(width: width, height: height)
        } else {
            content
                .frame(width: width)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
