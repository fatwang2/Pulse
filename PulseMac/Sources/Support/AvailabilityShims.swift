import Foundation
import SwiftUI

final class LockedValue<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) {
        self.value = value
    }

    func withLock<Result>(_ body: (inout Value) throws -> Result) rethrows -> Result {
        lock.lock()
        defer { lock.unlock() }
        return try body(&value)
    }
}

extension View {
    /// Soft scroll edge effect on macOS 26; earlier systems have no equivalent.
    @ViewBuilder
    func softScrollEdgeEffect(for edges: Edge.Set) -> some View {
        if #available(macOS 26, *) {
            scrollEdgeEffectStyle(.soft, for: edges)
        } else {
            self
        }
    }

    /// Glass prominent button on macOS 26, bordered prominent earlier.
    @ViewBuilder
    func prominentButtonStyle() -> some View {
        if #available(macOS 26, *) {
            buttonStyle(.glassProminent)
        } else {
            buttonStyle(.borderedProminent)
        }
    }

    @ViewBuilder
    func windowContainerBackgroundCompat() -> some View {
        if #available(macOS 15, *) {
            containerBackground(.thickMaterial, for: .window)
        } else {
            self
        }
    }

    @ViewBuilder
    func onScrollVisibilityChangeCompat(
        threshold: CGFloat,
        action: @escaping (Bool) -> Void
    ) -> some View {
        if #available(macOS 15, *) {
            onScrollVisibilityChange(threshold: threshold, action)
        } else {
            onGeometryChange(for: Bool.self) { proxy in
                let frame = proxy.frame(in: .scrollView)
                let bounds = proxy.bounds(of: .scrollView) ?? .zero
                let intersection = frame.intersection(bounds)
                return !intersection.isNull
                    && frame.width > 0
                    && intersection.width / frame.width >= threshold
            } action: { isVisible in
                action(isVisible)
            }
        }
    }
}

/// `ToolbarSpacer(.flexible)` on macOS 26; earlier systems rely on placement alone.
struct FlexibleToolbarSpacer: ToolbarContent {
    var body: some ToolbarContent {
        if #available(macOS 26, *) {
            ToolbarSpacer(.flexible)
        }
    }
}
