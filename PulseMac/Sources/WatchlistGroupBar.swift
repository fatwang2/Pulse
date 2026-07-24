import SwiftUI
import AppKit
import PulseCore
import UniformTypeIdentifiers

/// Compact, keyboard-addressable tag navigation for the menu-bar popover.
struct WatchlistGroupBar: View {
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let isDisabled: Bool
    let onSelect: (UUID) -> Void

    @State private var isCreating = false
    @State private var editingGroupID: UUID?
    @State private var nameDraft = ""
    @State private var nameHasError = false
    @State private var draggingGroupID: UUID?
    @State private var visibleGroupIDs: Set<UUID> = []
    @State private var shouldAnimateNextSelectionScroll = false
    @FocusState private var nameFieldFocused: Bool

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 4) {
                    ForEach(Array(appState.watchlist.groups.enumerated()), id: \.element.id) { index, group in
                        if editingGroupID == group.id {
                            nameField
                                .id(group.id)
                        } else {
                            WatchlistGroupTab(
                                name: group.name,
                                isSelected: appState.watchlist.selectedGroupID == group.id,
                                shortcutNumber: index < 9 ? index + 1 : nil
                            ) { pointerInitiated in
                                shouldAnimateNextSelectionScroll =
                                    pointerInitiated
                                    && !reduceMotion
                                    && appState.watchlist.selectedGroupID != group.id
                                cancelEditing()
                                onSelect(group.id)
                            }
                            .id(group.id)
                            .onScrollVisibilityChange(threshold: 0.9) { isVisible in
                                if isVisible {
                                    visibleGroupIDs.insert(group.id)
                                } else {
                                    visibleGroupIDs.remove(group.id)
                                }
                            }
                            .opacity(draggingGroupID == group.id ? 0.5 : 1)
                            .onDrag {
                                draggingGroupID = group.id
                                return NSItemProvider(object: group.id.uuidString as NSString)
                            }
                            .onDrop(
                                of: [UTType.plainText],
                                delegate: WatchlistGroupDropDelegate(
                                    destinationID: group.id,
                                    draggingGroupID: $draggingGroupID,
                                    move: appState.watchlist.moveGroup
                                )
                            )
                            .contextMenu {
                                Button(PulseLocalization.localizedString("watchlist.group.rename")) {
                                    beginRenaming(group)
                                }
                                if appState.watchlist.groups.count > 1 {
                                    Divider()
                                    Button(
                                        PulseLocalization.localizedString("watchlist.group.delete"),
                                        role: .destructive
                                    ) {
                                        deleteGroup(group)
                                    }
                                }
                            }
                        }
                    }

                    if isCreating {
                        nameField
                    } else {
                        Button(action: beginCreating) {
                            Image(systemName: "plus")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 22, height: 22)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.pressable)
                        .help(PulseLocalization.localizedString("watchlist.group.new"))
                    }
                }
                .padding(.horizontal, 1)
            }
            .scrollIndicators(.hidden)
            .onAppear { scrollToSelectedGroup(using: proxy) }
            .onChange(of: appState.watchlist.selectedGroupID) { _, _ in
                scrollToSelectedGroup(using: proxy)
            }
        }
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.45 : 1)
        .frame(height: 24)
    }

    private var nameField: some View {
        TextField(PulseLocalization.localizedString("watchlist.group.namePlaceholder"), text: $nameDraft)
            .textFieldStyle(.plain)
            .font(.system(size: 11.5, weight: .medium))
            .lineLimit(1)
            .padding(.horizontal, 8)
            .frame(width: 92, height: 22)
            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(
                        nameHasError
                            ? Color.red.opacity(0.75)
                            : Color(nsColor: .separatorColor).opacity(0.35),
                        lineWidth: 0.5
                    )
            }
            .focused($nameFieldFocused)
            .onSubmit { commitName() }
            .onExitCommand { cancelEditing() }
            .help(nameHasError ? PulseLocalization.localizedString("watchlist.group.nameError") : "")
    }

    private func beginCreating() {
        editingGroupID = nil
        isCreating = true
        nameDraft = ""
        nameHasError = false
        focusNameField()
    }

    private func beginRenaming(_ group: WatchlistGroup) {
        isCreating = false
        editingGroupID = group.id
        nameDraft = group.name
        nameHasError = false
        focusNameField()
    }

    private func deleteGroup(_ group: WatchlistGroup) {
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            _ = appState.watchlist.deleteGroup(group.id)
        }
    }

    private func focusNameField() {
        Task { @MainActor in nameFieldFocused = true }
    }

    private func scrollToSelectedGroup(using proxy: ScrollViewProxy) {
        guard let selectedGroupID = appState.watchlist.selectedGroupID else { return }

        guard !visibleGroupIDs.contains(selectedGroupID) else {
            shouldAnimateNextSelectionScroll = false
            return
        }

        if shouldAnimateNextSelectionScroll && !reduceMotion {
            withAnimation(.timingCurve(0.77, 0, 0.175, 1, duration: 0.18)) {
                proxy.scrollTo(selectedGroupID, anchor: .center)
            }
        } else {
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                proxy.scrollTo(selectedGroupID, anchor: .center)
            }
        }
        shouldAnimateNextSelectionScroll = false
    }

    private func commitName() {
        let succeeded: Bool
        if isCreating {
            // Creation is an occasional, direct action. If the new tag lands
            // outside the viewport, a short scroll helps reveal the result.
            shouldAnimateNextSelectionScroll = !reduceMotion
            succeeded = appState.watchlist.createGroup(named: nameDraft) != nil
        } else if let editingGroupID {
            succeeded = appState.watchlist.renameGroup(editingGroupID, to: nameDraft)
        } else {
            return
        }
        guard succeeded else {
            shouldAnimateNextSelectionScroll = false
            nameHasError = true
            focusNameField()
            return
        }
        cancelEditing()
    }

    private func cancelEditing() {
        isCreating = false
        editingGroupID = nil
        nameDraft = ""
        nameHasError = false
        nameFieldFocused = false
    }
}

private struct WatchlistGroupDropDelegate: DropDelegate {
    let destinationID: UUID
    @Binding var draggingGroupID: UUID?
    let move: (UUID, UUID) -> Void

    func dropEntered(info: DropInfo) {
        guard let draggingGroupID, draggingGroupID != destinationID else { return }
        move(draggingGroupID, destinationID)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggingGroupID = nil
        return true
    }
}

private struct WatchlistGroupTab: View {
    let name: String
    let isSelected: Bool
    let shortcutNumber: Int?
    let action: (_ pointerInitiated: Bool) -> Void
    @State private var hovering = false

    var body: some View {
        Group {
            if let shortcutNumber {
                button.keyboardShortcut(
                    KeyEquivalent(Character(String(shortcutNumber))),
                    modifiers: .command
                )
            } else {
                button
            }
        }
        .help(shortcutNumber.map { "\(name) (⌘\($0))" } ?? name)
    }

    private var button: some View {
        Button {
            action(isPointerInitiated)
        } label: {
            Text(name)
                .font(.system(size: 11.5, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? Color.accentColor : (hovering ? .primary : .secondary))
                .lineLimit(1)
                .padding(.horizontal, 9)
                .frame(height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(
                            isSelected
                                ? Color.accentColor.opacity(0.13)
                                : (hovering ? Color.primary.opacity(0.06) : .clear)
                        )
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .onHover { hovering = $0 }
    }

    private var isPointerInitiated: Bool {
        switch NSApp.currentEvent?.type {
        case .leftMouseDown, .leftMouseUp:
            true
        default:
            false
        }
    }
}
