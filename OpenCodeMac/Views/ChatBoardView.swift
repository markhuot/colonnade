import AppKit
import SwiftUI

struct ChatBoardView: View {
    @EnvironmentObject private var appState: OpenCodeAppModel
    @State private var transientPaneWidths: [String: CGFloat] = [:]
    @State private var draggedSessionID: String?
    @State private var draggedPaneOffset: CGFloat = 0

    let sessionIDs: [String]

    private let paneSpacing: CGFloat = 18
    var body: some View {
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
                    .padding(20)
                }
                .scrollIndicators(.visible)
                .onAppear {
                    pruneTransientPaneWidths()
                    scrollToFocusedSession(with: proxy, animated: false)
                }
                .onChange(of: appState.focusedSessionID) { _, _ in
                    scrollToFocusedSession(with: proxy)
                }
                .onChange(of: appState.openSessionIDs) { _, _ in
                    pruneTransientPaneWidths()
                    if let draggedSessionID, !sessionIDs.contains(draggedSessionID) {
                        self.draggedSessionID = nil
                        draggedPaneOffset = 0
                    }
                }
                .onChange(of: sessionIDs) { _, _ in
                    pruneTransientPaneWidths()
                    if let draggedSessionID, !sessionIDs.contains(draggedSessionID) {
                        self.draggedSessionID = nil
                        draggedPaneOffset = 0
                    }
                    scrollToFocusedSession(with: proxy)
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
                    sessionID: sessionID,
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
    let sessionID: String
    let displayedWidth: CGFloat
    let minWidth: CGFloat
    let maxWidth: CGFloat
    let onPreview: (CGFloat, Bool) -> Void
    let onCommit: (CGFloat, Bool) -> Void

    @State private var dragStartWidth: CGFloat?
    @State private var optionPressedAtDragStart = false
    @State private var cursorPushed = false
    @State private var isDragging = false

    var body: some View {
        Color.clear
            .frame(width: 12)
            .padding(.horizontal, 3)
            .contentShape(Rectangle())
            .onHover { hovering in
                guard !isDragging else { return }
                updateCursor(active: hovering)
            }
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .global)
                    .onChanged { value in
                        if dragStartWidth == nil {
                            dragStartWidth = displayedWidth
                            optionPressedAtDragStart = MacModifierKeyState.isOptionPressed()
                            isDragging = true
                            updateCursor(active: true)
                        }

                        guard let dragStartWidth else { return }
                        let translation = value.location.x - value.startLocation.x
                        let targetWidth = min(max(dragStartWidth + translation, minWidth), maxWidth)
                        onPreview(targetWidth, optionPressedAtDragStart)
                    }
                    .onEnded { value in
                        let translation = value.location.x - value.startLocation.x
                        if let dragStartWidth {
                            onCommit(min(max(dragStartWidth + translation, minWidth), maxWidth), optionPressedAtDragStart)
                        }

                        dragStartWidth = nil
                        optionPressedAtDragStart = false
                        isDragging = false
                        updateCursor(active: false)
                    }
            )
            .onDisappear {
                updateCursor(active: false)
            }
    }

    private func updateCursor(active: Bool) {
        if active, !cursorPushed {
            MacCursorStyle.pushPaneResize()
            cursorPushed = true
        } else if !active, cursorPushed {
            MacCursorStyle.pop()
            cursorPushed = false
        }
    }
}
