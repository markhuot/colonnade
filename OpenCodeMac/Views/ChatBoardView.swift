import AppKit
import SwiftUI

private struct ChatBoardPaneDescriptor: Equatable {
    let sessionID: String
    let width: CGFloat
}

struct ChatBoardView: View {
    @EnvironmentObject private var appState: OpenCodeAppModel
    @State private var transientPaneWidths: [String: CGFloat] = [:]
    @State private var draggedSessionID: String?
    @State private var draggedPaneOffset: CGFloat = 0
    @State private var draftRegistry = SessionDraftRegistry()

    let sessionIDs: [String]

    private let paneSpacing: CGFloat = 18
    private let paneOuterPadding: CGFloat = 20
    private let paneBottomPadding: CGFloat = 7
    var body: some View {
        let focusedSessionID = appState.focusedSessionID
        let paneDescriptors = sessionIDs.map { sessionID in
            ChatBoardPaneDescriptor(sessionID: sessionID, width: paneWidth(for: sessionID))
        }

        if sessionIDs.isEmpty {
            ContentUnavailableView(
                "No Open Sessions",
                systemImage: "rectangle.split.3x1",
                description: Text("Choose a session from the sidebar or create a new one.")
            )
        } else if let liveStore = appState.liveStore {
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 18) {
                        ForEach(sessionIDs, id: \.self) { sessionID in
                            paneView(for: sessionID, liveStore: liveStore)
                        }
                    }
                    .padding(.top, paneOuterPadding)
                    .padding(.horizontal, paneOuterPadding)
                    .padding(.bottom, paneBottomPadding)
                }
                .scrollIndicators(.visible)
                .onAppear {
                    pruneTransientPaneWidths()
                    scrollToFocusedSession(with: proxy, animated: false)
                }
                .onChange(of: focusedSessionID) { _, _ in
                    scrollToFocusedSession(with: proxy)
                }
                .onChange(of: paneDescriptors) { _, _ in
                    pruneTransientPaneWidths()
                    if let draggedSessionID, !sessionIDs.contains(draggedSessionID) {
                        self.draggedSessionID = nil
                        draggedPaneOffset = 0
                    }
                    scrollToFocusedSession(with: proxy)
                }
                .onChange(of: sessionIDs) { _, newValue in
                    draftRegistry.retain(only: newValue)
                }
            }
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func paneWidth(for sessionID: String) -> CGFloat {
        transientPaneWidths[sessionID] ?? appState.paneWidth(for: sessionID)
    }

    @ViewBuilder
    private func paneView(for sessionID: String, liveStore: WorkspaceLiveStore) -> some View {
        let width = paneWidth(for: sessionID)
        let state = liveStore.sessionState(for: sessionID)

        SessionColumnView(
            sessionState: state,
            draftState: draftRegistry.state(for: sessionID),
            sessionID: sessionID,
            onPaneDragChanged: { translation in
                handlePaneDragChanged(sessionID: sessionID, translation: translation)
            },
            onPaneDragEnded: {
                handlePaneDragEnded(sessionID: sessionID)
            }
        )
            .id(sessionID)
            .frame(width: width)
            .offset(x: draggedSessionID == sessionID ? draggedPaneOffset : 0)
            .zIndex(draggedSessionID == sessionID ? 1 : 0)
            .overlay(alignment: Alignment.trailing) {
                PaneResizeHandle(
                    displayedWidth: width,
                    minWidth: appState.minPaneWidth,
                    maxWidth: appState.maxPaneWidth,
                    onPreview: { width, equalizeAll in
                        previewPaneWidth(sessionID: sessionID, width: width, equalizeAll: equalizeAll)
                    },
                    onCommit: { width, equalizeAll in
                        commitPaneWidth(sessionID: sessionID, width: width, equalizeAll: equalizeAll)
                    }
                )
                .offset(x: 9)
            }
    }

    private func previewPaneWidth(sessionID: String, width: CGFloat, equalizeAll: Bool) {
        let clampedWidth = min(max(width, appState.minPaneWidth), appState.maxPaneWidth)

        if equalizeAll {
            transientPaneWidths = Dictionary(uniqueKeysWithValues: sessionIDs.map { ($0, clampedWidth) })
        } else {
            transientPaneWidths[sessionID] = clampedWidth
        }
    }

    private func commitPaneWidth(sessionID: String, width: CGFloat, equalizeAll: Bool) {
        let clampedWidth = min(max(width, appState.minPaneWidth), appState.maxPaneWidth)
        appState.setPaneWidth(sessionID: sessionID, width: clampedWidth, equalizeAll: equalizeAll, persist: true)
        transientPaneWidths.removeAll()
    }

    private func pruneTransientPaneWidths() {
        transientPaneWidths = transientPaneWidths.filter { sessionIDs.contains($0.key) }
    }

    private func handlePaneDragChanged(sessionID: String, translation: CGFloat) {
        if draggedSessionID != sessionID {
            draggedSessionID = sessionID
        }

        draggedPaneOffset = translation

        guard let sourceIndex = sessionIDs.firstIndex(of: sessionID) else { return }
        let paneFrames = paneFrames(for: sessionIDs)
        let draggedMidX = paneFrames[sourceIndex].midX + translation

        if sourceIndex > 0, draggedMidX < paneFrames[sourceIndex - 1].midX {
            withAnimation(.easeInOut(duration: 0.15)) {
                appState.moveOpenSession(sessionID, before: sessionIDs[sourceIndex - 1], persist: false, sync: false)
            }
            return
        }

        if sourceIndex < sessionIDs.count - 1, draggedMidX > paneFrames[sourceIndex + 1].midX {
            let insertionIndex = sourceIndex + 2
            let targetSessionID = sessionIDs.indices.contains(insertionIndex) ? sessionIDs[insertionIndex] : nil
            withAnimation(.easeInOut(duration: 0.15)) {
                appState.moveOpenSession(sessionID, before: targetSessionID, persist: false, sync: false)
            }
        }
    }

    private func handlePaneDragEnded(sessionID: String) {
        guard draggedSessionID == sessionID else { return }

        appState.commitOpenSessionOrder()
        withAnimation(.easeInOut(duration: 0.15)) {
            draggedSessionID = nil
            draggedPaneOffset = 0
        }
    }

    private func paneFrames(for sessionIDs: [String]) -> [CGRect] {
        var nextMinX: CGFloat = 0

        return sessionIDs.map { sessionID in
            let frame = CGRect(x: nextMinX, y: 0, width: paneWidth(for: sessionID), height: 0)
            nextMinX += frame.width + paneSpacing
            return frame
        }
    }

    private func scrollToFocusedSession(with proxy: ScrollViewProxy, animated: Bool = true) {
        guard let focusedSessionID = appState.focusedSessionID, sessionIDs.contains(focusedSessionID) else { return }

        let action: () -> Void = {
            proxy.scrollTo(focusedSessionID, anchor: .center)
        }

        if animated {
            withAnimation(.easeInOut(duration: 0.2)) {
                action()
            }
        } else {
            action()
        }
    }
}

private struct PaneResizeHandle: View {
    let displayedWidth: CGFloat
    let minWidth: CGFloat
    let maxWidth: CGFloat
    let onPreview: (CGFloat, Bool) -> Void
    let onCommit: (CGFloat, Bool) -> Void

    var body: some View {
        PaneResizeHandleBridge(
            displayedWidth: displayedWidth,
            minWidth: minWidth,
            maxWidth: maxWidth,
            onPreview: onPreview,
            onCommit: onCommit
        )
            .frame(width: 12)
            .padding(.horizontal, 3)
    }
}

private struct PaneResizeHandleBridge: NSViewRepresentable {
    let displayedWidth: CGFloat
    let minWidth: CGFloat
    let maxWidth: CGFloat
    let onPreview: (CGFloat, Bool) -> Void
    let onCommit: (CGFloat, Bool) -> Void

    func makeNSView(context: Context) -> PaneResizeHandleNSView {
        let view = PaneResizeHandleNSView()
        view.displayedWidth = displayedWidth
        view.minWidth = minWidth
        view.maxWidth = maxWidth
        view.onPreview = onPreview
        view.onCommit = onCommit
        return view
    }

    func updateNSView(_ nsView: PaneResizeHandleNSView, context: Context) {
        nsView.displayedWidth = displayedWidth
        nsView.minWidth = minWidth
        nsView.maxWidth = maxWidth
        nsView.onPreview = onPreview
        nsView.onCommit = onCommit
    }
}

private final class PaneResizeHandleNSView: NSView {
    var displayedWidth: CGFloat = 0
    var minWidth: CGFloat = 0
    var maxWidth: CGFloat = 0
    var onPreview: ((CGFloat, Bool) -> Void)?
    var onCommit: ((CGFloat, Bool) -> Void)?

    private var dragStartWidth: CGFloat?
    private var dragStartLocationX: CGFloat?
    private var optionPressedAtDragStart = false
    private var trackingArea: NSTrackingArea?

    override var mouseDownCanMoveWindow: Bool {
        false
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateTrackingAreas() {
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }

        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .inVisibleRect, .mouseEnteredAndExited],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        self.trackingArea = trackingArea

        super.updateTrackingAreas()
    }

    override func resetCursorRects() {
        discardCursorRects()
        addCursorRect(bounds, cursor: .resizeLeftRight)
    }

    override func mouseDown(with event: NSEvent) {
        dragStartWidth = displayedWidth
        dragStartLocationX = event.locationInWindow.x
        optionPressedAtDragStart = event.modifierFlags.contains(.option)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragStartWidth, let dragStartLocationX else { return }
        onPreview?(clampedWidth(for: dragStartWidth, translation: event.locationInWindow.x - dragStartLocationX), optionPressedAtDragStart)
    }

    override func mouseUp(with event: NSEvent) {
        guard let dragStartWidth, let dragStartLocationX else {
            clearDragState()
            return
        }

        onCommit?(clampedWidth(for: dragStartWidth, translation: event.locationInWindow.x - dragStartLocationX), optionPressedAtDragStart)
        clearDragState()
    }

    private func clampedWidth(for startWidth: CGFloat, translation: CGFloat) -> CGFloat {
        min(max(startWidth + translation, minWidth), maxWidth)
    }

    private func clearDragState() {
        dragStartWidth = nil
        dragStartLocationX = nil
        optionPressedAtDragStart = false
    }
}
