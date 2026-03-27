import AppKit
import SwiftUI

@MainActor
private enum ViewRenderDebugRegistry {
    private static var counts: [String: ViewRenderDebugCounts] = [:]

    static func recordBody(for key: String) -> Int {
        guard DebugRuntime.isViewRenderCountersEnabled else { return 0 }
        var snapshot = counts[key, default: .init()]
        snapshot.body += 1
        counts[key] = snapshot
        return snapshot.body
    }

    static func recordAppear(for key: String) -> ViewRenderDebugCounts {
        guard DebugRuntime.isViewRenderCountersEnabled else { return .init() }
        return mutate(key) { $0.appear += 1 }
    }

    static func recordDisappear(for key: String) -> ViewRenderDebugCounts {
        guard DebugRuntime.isViewRenderCountersEnabled else { return .init() }
        return mutate(key) { $0.disappear += 1 }
    }

    static func recordUpdate(for key: String, bodyCount: Int) -> ViewRenderDebugCounts {
        guard DebugRuntime.isViewRenderCountersEnabled else { return .init() }
        return mutate(key) {
            $0.body = max($0.body, bodyCount)
            $0.update += 1
        }
    }

    static func snapshot(for key: String) -> ViewRenderDebugCounts {
        guard DebugRuntime.isViewRenderCountersEnabled else { return .init() }
        return counts[key, default: .init()]
    }

    private static func mutate(_ key: String, _ body: (inout ViewRenderDebugCounts) -> Void) -> ViewRenderDebugCounts {
        var snapshot = counts[key, default: .init()]
        body(&snapshot)
        counts[key] = snapshot
        return snapshot
    }
}

private struct ViewRenderDebugCounts {
    var body = 0
    var appear = 0
    var disappear = 0
    var update = 0

    var label: String {
        "b:\(body) a:\(appear) d:\(disappear) u:\(update)"
    }
}

private struct ViewRenderDebugBadge: NSViewRepresentable {
    let key: String
    let bodyCount: Int

    @MainActor
    func makeNSView(context: Context) -> ViewRenderDebugBadgeNSView {
        let view = ViewRenderDebugBadgeNSView(debugKey: key)
        view.apply(snapshot: ViewRenderDebugRegistry.snapshot(for: key))
        return view
    }

    @MainActor
    func updateNSView(_ nsView: ViewRenderDebugBadgeNSView, context: Context) {
        nsView.debugKey = key
        nsView.apply(snapshot: ViewRenderDebugRegistry.recordUpdate(for: key, bodyCount: bodyCount))
    }
}

private extension View {
    @ViewBuilder
    func renderDebugBadgeOverlay(key: String, bodyCount: Int) -> some View {
        if DebugRuntime.isViewRenderCountersEnabled {
            overlay(alignment: .bottomTrailing) {
                ViewRenderDebugBadge(key: key, bodyCount: bodyCount)
                    .fixedSize()
                    .padding(8)
            }
        } else {
            self
        }
    }
}

@MainActor
private final class ViewRenderDebugBadgeNSView: NSView {
    var debugKey: String

    private let textField = NSTextField(labelWithString: "")
    private var lastKnownWindowState = false

    init(debugKey: String) {
        self.debugKey = debugKey
        super.init(frame: .zero)
        setContentHuggingPriority(.required, for: .horizontal)
        setContentHuggingPriority(.required, for: .vertical)
        setContentCompressionResistancePriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .vertical)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.78).cgColor
        layer?.shadowColor = NSColor.black.withAlphaComponent(0.28).cgColor
        layer?.shadowOpacity = 1
        layer?.shadowRadius = 10
        layer?.shadowOffset = CGSize(width: 0, height: -4)

        textField.font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .semibold)
        textField.textColor = .white
        textField.lineBreakMode = .byClipping
        addSubview(textField)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        textField.frame = bounds.insetBy(dx: 6, dy: 4)
    }

    override var intrinsicContentSize: NSSize {
        let labelSize = textField.intrinsicContentSize
        return NSSize(width: labelSize.width + 12, height: labelSize.height + 8)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        let isVisible = window != nil
        guard isVisible != lastKnownWindowState else { return }
        lastKnownWindowState = isVisible

        let snapshot = if isVisible {
            ViewRenderDebugRegistry.recordAppear(for: debugKey)
        } else {
            ViewRenderDebugRegistry.recordDisappear(for: debugKey)
        }

        apply(snapshot: snapshot)
    }

    func apply(snapshot: ViewRenderDebugCounts) {
        textField.stringValue = snapshot.label
        invalidateIntrinsicContentSize()
        needsLayout = true
    }
}

private extension View {
    @ViewBuilder
    func clipPaneContent(if condition: Bool, cornerRadius: CGFloat) -> some View {
        if condition {
            clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            self
        }
    }
}

private struct PaneShadowModifier: ViewModifier {
    let isFocused: Bool

    func body(content: Content) -> some View {
        if isFocused {
            content.shadow(color: .black.opacity(0.20), radius: 18, x: 0, y: 8)
        } else {
            content
        }
    }
}

enum PaneFocusOutlineState {
    static func showsFocusOutline(
        chrome: SessionColumnChrome,
        openSessionCount: Int,
        focusedSessionID: String?,
        sessionID: String,
        paneHasFocus: Bool
    ) -> Bool {
        let isSelectedSession = focusedSessionID == sessionID

        guard chrome == .pane, openSessionCount > 1 else {
            return isSelectedSession
        }

        return isSelectedSession && paneHasFocus
    }
}

private struct PaneFocusContainer<Content: View>: NSViewRepresentable {
    @Binding var isFocused: Bool
    let onFocus: () -> Void
    let content: Content

    init(
        isFocused: Binding<Bool>,
        onFocus: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        _isFocused = isFocused
        self.onFocus = onFocus
        self.content = content()
    }

    func makeNSView(context: Context) -> PaneFocusContainerNSView<Content> {
        PaneFocusContainerNSView(rootView: content, isFocused: $isFocused, onFocus: onFocus)
    }

    func updateNSView(_ nsView: PaneFocusContainerNSView<Content>, context: Context) {
        nsView.update(rootView: content, isFocused: $isFocused, onFocus: onFocus)
    }
}

private final class PaneFocusContainerNSView<Content: View>: NSView {
    private let hostingView: NSHostingView<Content>
    private var isFocusedBinding: Binding<Bool>
    private var onFocus: () -> Void
    private weak var observedWindow: NSWindow?

    override var acceptsFirstResponder: Bool {
        true
    }

    override var canBecomeKeyView: Bool {
        true
    }

    init(rootView: Content, isFocused: Binding<Bool>, onFocus: @escaping () -> Void) {
        hostingView = NSHostingView(rootView: rootView)
        isFocusedBinding = isFocused
        self.onFocus = onFocus
        super.init(frame: .zero)

        translatesAutoresizingMaskIntoConstraints = false
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hostingView)

        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard observedWindow !== window else {
            updateFocusState()
            return
        }

        removeWindowObservers()
        observedWindow = window
        installWindowObservers()
        updateFocusState()
    }

    override func becomeFirstResponder() -> Bool {
        let didBecomeFirstResponder = super.becomeFirstResponder()
        updateFocusState()
        return didBecomeFirstResponder
    }

    override func resignFirstResponder() -> Bool {
        let didResignFirstResponder = super.resignFirstResponder()
        updateFocusState()
        return didResignFirstResponder
    }

    func update(rootView: Content, isFocused: Binding<Bool>, onFocus: @escaping () -> Void) {
        hostingView.rootView = rootView
        isFocusedBinding = isFocused
        self.onFocus = onFocus
        updateFocusState()
    }

    private func installWindowObservers() {
        guard let window = observedWindow else {
            isFocusedBinding.wrappedValue = false
            return
        }

        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(handleWindowStateChange), name: NSWindow.didBecomeKeyNotification, object: window)
        center.addObserver(self, selector: #selector(handleWindowStateChange), name: NSWindow.didResignKeyNotification, object: window)
        center.addObserver(self, selector: #selector(handleWindowStateChange), name: NSWindow.didBecomeMainNotification, object: window)
        center.addObserver(self, selector: #selector(handleWindowStateChange), name: NSWindow.didResignMainNotification, object: window)
        center.addObserver(self, selector: #selector(handleWindowStateChange), name: NSWindow.didUpdateNotification, object: window)
    }

    private func removeWindowObservers() {
        guard let window = observedWindow else { return }

        let center = NotificationCenter.default
        center.removeObserver(self, name: NSWindow.didBecomeKeyNotification, object: window)
        center.removeObserver(self, name: NSWindow.didResignKeyNotification, object: window)
        center.removeObserver(self, name: NSWindow.didBecomeMainNotification, object: window)
        center.removeObserver(self, name: NSWindow.didResignMainNotification, object: window)
        center.removeObserver(self, name: NSWindow.didUpdateNotification, object: window)
        observedWindow = nil
    }

    @objc
    private func handleWindowStateChange() {
        updateFocusState()
    }

    private func updateFocusState() {
        guard let window else {
            isFocusedBinding.wrappedValue = false
            return
        }

        let isFocused = window.isKeyWindow && containsFirstResponder(window.firstResponder)
        let didChangeFocus = isFocusedBinding.wrappedValue != isFocused
        isFocusedBinding.wrappedValue = isFocused

        if isFocused, didChangeFocus {
            onFocus()
        }
    }

    private func containsFirstResponder(_ responder: NSResponder?) -> Bool {
        switch responder {
        case nil:
            false
        case let responder as NSView:
            responder.isDescendant(of: self)
        case let responder as NSViewController:
            responder.view.isDescendant(of: self)
        default:
            responder === self || responder === hostingView
        }
    }
}

struct SessionColumnView: View {
    static let paneCornerRadius: CGFloat = 24

    @EnvironmentObject private var appState: OpenCodeAppModel
    @Environment(\.openCodeTheme) private var theme
    @State private var paneHasFocus = false
    @ObservedObject var sessionState: SessionLiveState
    let draftState: SessionDraftState

    let sessionID: String
    var chrome: SessionColumnChrome = .pane
    var showsDiff = false
    var onToggleDiff: (() -> Void)? = nil
    var onPaneDragChanged: ((CGFloat) -> Void)? = nil
    var onPaneDragEnded: (() -> Void)? = nil

    var body: some View {
        let session = sessionState.session
        let transcriptRows = sessionState.transcriptRows
        let questions = appState.questionForSession(sessionID)
        let permissions = deduplicatedPermissions(sessionState.permissions)
        let availableSessions = appState.sessions
        let workspaceConnection = appState.workspaceConnection
        let thinkingBannerTitle = latestThinkingBannerTitle(
            session: session,
            latestReasoningTitle: sessionState.latestReasoningTitle,
            questions: questions,
            permissions: permissions
        )
        PaneFocusContainer(isFocused: $paneHasFocus, onFocus: {
            guard appState.focusedSessionID != sessionID else { return }
            appState.focusSession(sessionID)
        }) {
            HStack(spacing: 0) {
                sessionPaneContent(
                    session: session,
                    transcriptRows: transcriptRows,
                    questions: questions,
                    permissions: permissions,
                    availableSessions: availableSessions,
                    workspaceConnection: workspaceConnection,
                    thinkingBannerTitle: thinkingBannerTitle
                )

                if showsDiff {
                    Divider()

                    SessionDiffDrawerView(
                        sessionState: sessionState,
                        onClose: {
                            onToggleDiff?()
                        }
                    )
                    .frame(width: SessionDiffDrawerMetrics.macDrawerWidth)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipPaneContent(if: chrome == .pane, cornerRadius: Self.paneCornerRadius)
        .background(backgroundView)
        .overlay { overlayView }
        .contentShape(Rectangle())
        .animation(.easeInOut(duration: 0.22), value: showsDiff)
        .onChange(of: showsDiff) { _, newValue in
            guard newValue else { return }
            if case .idle = sessionState.diffLoadState {
                appState.refreshDiff(for: sessionID)
            }
        }
    }

    @ViewBuilder
    private func sessionPaneContent(
        session: SessionDisplay?,
        transcriptRows: [TranscriptMessageRow],
        questions: [QuestionRequest],
        permissions: [PermissionRequest],
        availableSessions: [SessionDisplay],
        workspaceConnection: WorkspaceConnection?,
        thinkingBannerTitle: String?
    ) -> some View {
        VStack(spacing: 0) {
            if chrome == .pane {
                SessionHeaderView(
                    sessionID: sessionID,
                    session: session,
                    indicator: session?.indicator ?? SessionIndicator.resolve(status: nil, hasPendingPermission: false),
                    contextUsageText: session?.contextUsageText,
                    allowsPaneDrag: chrome == .pane,
                    showsDiff: showsDiff,
                    onToggleDiff: onToggleDiff,
                    onPaneDragChanged: onPaneDragChanged,
                    onPaneDragEnded: onPaneDragEnded
                )
                Divider()
            }
            SessionTranscriptSection(
                snapshot: SessionTranscriptSnapshot(
                    transcriptRows: transcriptRows,
                    questions: questions,
                    thinkingBannerTitle: thinkingBannerTitle,
                    availableSessions: availableSessions,
                    latestTodoToolPartID: sessionState.latestTodoToolPartID,
                    workspaceConnection: workspaceConnection
                ),
                sessionState: sessionState,
                onFocusSession: { sessionID in
                    appState.focusSession(sessionID)
                },
                onAnswerQuestion: { request, answers in
                    appState.answerQuestion(request, answers: answers)
                },
                onRejectQuestion: { request in
                    appState.rejectQuestion(request)
                }
            )
            .equatable()
            Divider()
            SessionComposerSection(
                draftState: draftState,
                sessionID: sessionID,
                permissions: permissions,
                isFocused: isFocused,
                focusSession: {
                    appState.focusSession(sessionID)
                },
                focusPermissionPrompt: {
                    appState.focusSession(sessionID, focusPrompt: true)
                },
                answerPermission: { request, reply in
                    appState.answerPermission(request, reply: reply)
                },
                sendMessage: { draft in
                    appState.sendMessage(sessionID: sessionID, text: draft)
                },
                commandSuggestionProvider: { draft, cursorLocation in
                    appState.slashCommandSuggestions(for: draft, sessionID: sessionID, cursorLocation: cursorLocation)
                },
                applySlashCommandSuggestion: { option, draft in
                    appState.applyingSlashCommandSuggestion(option, to: draft, sessionID: sessionID)
                },
                modelOptionsProvider: {
                    appState.modelOptions(for: sessionID)
                },
                agentOptionsProvider: {
                    appState.agentOptions(for: sessionID)
                },
                selectedModelOptionProvider: {
                    appState.selectedModelOption(for: sessionID)
                },
                selectedAgentKey: Binding(
                    get: {
                        let agentOptions = appState.agentOptions(for: sessionID)
                        return appState.selectedAgentOption(for: sessionID)?.id ?? agentOptions.first?.id ?? ""
                    },
                    set: { appState.setSelectedAgent($0, for: sessionID) }
                ),
                selectedModelKey: Binding(
                    get: {
                        let modelOptions = appState.modelOptions(for: sessionID)
                        return appState.selectedModelOption(for: sessionID)?.id ?? modelOptions.first?.id ?? ""
                    },
                    set: { appState.setSelectedModel($0, for: sessionID, updateDefault: MacModifierKeyState.isOptionPressed()) }
                ),
                selectedThinkingLevel: Binding(
                    get: {
                        let selectedModelOption = appState.selectedModelOption(for: sessionID)
                        let thinkingLevels = [OpenCodeAppModel.defaultThinkingLevel] + (selectedModelOption?.thinkingLevels ?? [])
                        return appState.selectedThinkingLevel(for: sessionID) ?? thinkingLevels.first ?? ""
                    },
                    set: { appState.setSelectedThinkingLevel($0, for: sessionID) }
                ),
                composerFocusRequestID: appState.promptFocusRequest?.sessionID == sessionID ? appState.promptFocusRequest?.id : nil
            )
        }
    }

    private func deduplicatedPermissions(_ permissions: [PermissionRequest]) -> [PermissionRequest] {
        var seenKeys = Set<SessionPermissionPresentationKey>()
        return permissions.filter { request in
            guard !appState.isPermissionDismissed(request) else { return false }
            let key = SessionPermissionPresentationKey(request: request)
            return seenKeys.insert(key).inserted
        }
    }

    private var borderColor: Color {
        showsFocusOutline ? theme.accent.opacity(0.85) : theme.border.opacity(0.7)
    }

    private var isFocused: Bool {
        showsFocusOutline
    }

    private var showsFocusOutline: Bool {
        PaneFocusOutlineState.showsFocusOutline(
            chrome: chrome,
            openSessionCount: appState.openSessionIDs.count,
            focusedSessionID: appState.focusedSessionID,
            sessionID: sessionID,
            paneHasFocus: paneHasFocus
        )
    }

    @ViewBuilder
    private var backgroundView: some View {
        switch chrome {
        case .pane:
            RoundedRectangle(cornerRadius: Self.paneCornerRadius, style: .continuous)
                .fill(theme.surfaceBackground)
                .modifier(PaneShadowModifier(isFocused: isFocused))
        case .window:
            theme.surfaceBackground
        }
    }

    @ViewBuilder
    private var overlayView: some View {
        if chrome == .pane {
            RoundedRectangle(cornerRadius: Self.paneCornerRadius, style: .continuous)
                .strokeBorder(borderColor, lineWidth: showsFocusOutline ? 2 : 1)
        }
    }

    private func latestThinkingBannerTitle(
        session: SessionDisplay?,
        latestReasoningTitle: String?,
        questions: [QuestionRequest],
        permissions: [PermissionRequest]
    ) -> String? {
        SessionTranscriptSupport.thinkingBannerTitle(
            session: session,
            latestReasoningTitle: latestReasoningTitle,
            questions: questions,
            permissions: permissions
        )
    }
}

private struct SessionTranscriptSnapshot: Equatable {
    let transcriptRows: [TranscriptMessageRow]
    let questions: [QuestionRequest]
    let thinkingBannerTitle: String?
    let availableSessions: [SessionDisplay]
    let latestTodoToolPartID: String?
    let workspaceConnection: WorkspaceConnection?
}

private struct SessionTranscriptSection: View, Equatable {
    let snapshot: SessionTranscriptSnapshot
    @ObservedObject var sessionState: SessionLiveState
    let onFocusSession: (String) -> Void
    let onAnswerQuestion: (QuestionRequest, [[String]]) -> Void
    let onRejectQuestion: (QuestionRequest) -> Void

    nonisolated static func == (lhs: SessionTranscriptSection, rhs: SessionTranscriptSection) -> Bool {
        lhs.snapshot == rhs.snapshot
    }

    var body: some View {
        SessionTimelineView(
            sessionState: sessionState,
            transcriptRows: snapshot.transcriptRows,
            questions: snapshot.questions,
            thinkingBannerTitle: snapshot.thinkingBannerTitle,
            availableSessions: snapshot.availableSessions,
            latestTodoToolPartID: snapshot.latestTodoToolPartID,
            workspaceConnection: snapshot.workspaceConnection,
            onFocusSession: onFocusSession,
            onAnswerQuestion: onAnswerQuestion,
            onRejectQuestion: onRejectQuestion
        )
    }
}

private struct SessionComposerSection: View {
    @EnvironmentObject private var appState: OpenCodeAppModel
    @ObservedObject var draftState: SessionDraftState

    let sessionID: String
    let permissions: [PermissionRequest]
    let isFocused: Bool
    let focusSession: () -> Void
    let focusPermissionPrompt: () -> Void
    let answerPermission: (PermissionRequest, PermissionReply) -> Void
    let sendMessage: (String) -> Bool
    let commandSuggestionProvider: (String, Int) -> [CommandOption]
    let applySlashCommandSuggestion: (CommandOption, String) -> String?
    let modelOptionsProvider: () -> [ModelOption]
    let agentOptionsProvider: () -> [AgentOption]
    let selectedModelOptionProvider: () -> ModelOption?
    let selectedAgentKey: Binding<String>
    let selectedModelKey: Binding<String>
    let selectedThinkingLevel: Binding<String>
    let composerFocusRequestID: UUID?

    var body: some View {
        let draft = Binding(
            get: { draftState.text },
            set: { draftState.text = $0 }
        )
        let modelOptions = modelOptionsProvider()
        let agentOptions = agentOptionsProvider()
        let selectedModelOption = selectedModelOptionProvider()
        let thinkingLevels = [OpenCodeAppModel.defaultThinkingLevel] + (selectedModelOption?.thinkingLevels ?? [])

        SessionComposerView(
            sessionID: sessionID,
            permissions: permissions,
            isFocused: isFocused,
            draft: draft,
            composerFocusRequestID: composerFocusRequestID,
            agentOptions: agentOptions,
            modelOptions: modelOptions,
            selectedModelSupportsReasoning: selectedModelOption?.supportsReasoning == true,
            thinkingLevels: thinkingLevels,
            selectedAgentKey: selectedAgentKey,
            selectedModelKey: selectedModelKey,
            selectedThinkingLevel: selectedThinkingLevel,
            commandSuggestionProvider: { cursorLocation in
                commandSuggestionProvider(draftState.text, cursorLocation)
            },
            applySlashCommandSuggestion: { option in
                guard let updatedDraft = applySlashCommandSuggestion(option, draftState.text) else { return }
                draftState.text = updatedDraft
            },
            focusSession: focusSession,
            focusPermissionPrompt: focusPermissionPrompt,
            answerPermission: answerPermission,
            sendMessage: {
                let currentDraft = draftState.text
                let didSend = sendMessage(currentDraft)
                if didSend {
                    draftState.text = ""
                }
                return didSend
            }
        )
    }
}

enum SessionColumnChrome {
    case pane
    case window
}

private struct SessionHeaderView: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var appState: OpenCodeAppModel
    @Environment(\.openCodeTheme) private var theme

    let sessionID: String
    let session: SessionDisplay?
    let indicator: SessionIndicator
    let contextUsageText: String?
    var allowsPaneDrag = false
    var showsDiff = false
    var onToggleDiff: (() -> Void)? = nil
    var onPaneDragChanged: ((CGFloat) -> Void)? = nil
    var onPaneDragEnded: (() -> Void)? = nil

    @State private var isHoveringStatusIcon = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Button {
                            appState.closeSession(sessionID)
                        } label: {
                            Group {
                                if isHoveringStatusIcon {
                                    Image(systemName: "xmark")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(theme.secondaryText)
                                } else {
                                    SessionStatusIcon(color: indicator.color())
                                }
                            }
                            .frame(width: 14, height: 14)
                            .offset(y: -6)
                        }
                        .alignmentGuide(.firstTextBaseline) { dimensions in
                            dimensions[VerticalAlignment.center]
                        }
                        .buttonStyle(.plain)
                        .help("Close Pane")
                        .onHover { hovering in
                            isHoveringStatusIcon = hovering
                        }

                        Text(session?.title ?? sessionID)
                            .font(.title3.weight(.semibold))
                            .lineLimit(2)
                    }

                    Text(contextUsageText ?? "No context usage yet")
                        .font(.caption)
                        .foregroundStyle(theme.secondaryText)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    appState.focusSession(sessionID)
                }

                Spacer(minLength: 10)

                HStack(spacing: 8) {
                    if let onToggleDiff {
                        Button(action: onToggleDiff) {
                            Label("Diff", systemImage: "doc.text.magnifyingglass")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(showsDiff ? theme.accentSubtleBackground : theme.mutedSurfaceBackground)
                                )
                        }
                        .buttonStyle(.plain)
                    }

                    Button {
                        if let workspaceConnection = appState.workspaceConnection {
                            openWindow(
                                id: "session-window",
                                value: SessionWindowContext(connection: workspaceConnection, sessionID: sessionID)
                            )
                        }
                    } label: {
                        Image(systemName: "arrow.up.forward.square")
                    }
                    .buttonStyle(.plain)
                }
                .font(.headline)
            }
        }
        .padding(18)
        .modifier(SessionHeaderDragModifier(
            allowsPaneDrag: allowsPaneDrag,
            onPaneDragChanged: onPaneDragChanged,
            onPaneDragEnded: onPaneDragEnded
        ))
    }
}

private struct SessionHeaderDragModifier: ViewModifier {
    let allowsPaneDrag: Bool
    let onPaneDragChanged: ((CGFloat) -> Void)?
    let onPaneDragEnded: (() -> Void)?

    @ViewBuilder
    func body(content: Content) -> some View {
        if allowsPaneDrag {
            content
                .contentShape(Rectangle())
                .simultaneousGesture(
                    DragGesture(minimumDistance: 6, coordinateSpace: .global)
                        .onChanged { value in
                            onPaneDragChanged?(value.translation.width)
                        }
                        .onEnded { _ in
                            onPaneDragEnded?()
                        }
                )
        } else {
            content
        }
    }
}

private struct SessionTimelineView: View {
    @Environment(\.openCodeTheme) private var theme

    @ObservedObject var sessionState: SessionLiveState
    let transcriptRows: [TranscriptMessageRow]
    let questions: [QuestionRequest]
    let thinkingBannerTitle: String?
    let availableSessions: [SessionDisplay]
    let latestTodoToolPartID: String?
    let workspaceConnection: WorkspaceConnection?
    let onFocusSession: (String) -> Void
    let onAnswerQuestion: (QuestionRequest, [[String]]) -> Void
    let onRejectQuestion: (QuestionRequest) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                ForEach(transcriptRows) { row in
                    if let messageState = sessionState.messageState(for: row.id) {
                        MessageRowView(
                            messageState: messageState,
                            showsTimestamp: row.showsTimestamp,
                            availableSessions: availableSessions,
                            latestTodoToolPartID: latestTodoToolPartID,
                            workspaceConnection: workspaceConnection,
                            onInteraction: {
                                onFocusSession(messageState.info.sessionID)
                            }
                        )
                    }
                }

                ForEach(questions) { request in
                    QuestionCard(
                        request: request,
                        onSubmitAnswers: { answers in
                            onAnswerQuestion(request, answers)
                        },
                        onReject: {
                            onRejectQuestion(request)
                        }
                    )
                }

                if let thinkingBannerTitle {
                    ThinkingStatusBanner(title: thinkingBannerTitle)
                        .padding(.top, 4)
                        .padding(.leading, TimelineMessageLayout.leadingOffset(for: TimelineMessageLayout.messageCardPadding))
                        .transition(.asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal: .move(edge: .top).combined(with: .opacity)
                        ))
                }
            }
            .padding(18)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .layoutPriority(1)
        .defaultScrollAnchor(.bottom)
        .background(theme.mutedSurfaceBackground.opacity(0.8))
    }
}

private struct SessionComposerView: View {
    @Environment(\.openCodeTheme) private var theme

    private static let placeholderOptions = [
        "Let's get started!",
        "What are we working on now?",
        "What should we tackle next?",
        "How can I help?"
    ]

    @State private var promptHeight = PromptTextView.defaultHeight
    @State private var highlightedCommandSuggestionIndex: Int? = 0
    @State private var promptCursorLocation = 0
    @State private var promptSuggestionAnchor: CGRect = .zero
    @State private var placeholderText = Self.placeholderOptions.randomElement() ?? "Let's get started!"
    @State private var lastAutoFocusedPermissionID: String?
    let sessionID: String
    let permissions: [PermissionRequest]
    let isFocused: Bool
    let draft: Binding<String>
    let composerFocusRequestID: UUID?
    let agentOptions: [AgentOption]
    let modelOptions: [ModelOption]
    let selectedModelSupportsReasoning: Bool
    let thinkingLevels: [String]
    let selectedAgentKey: Binding<String>
    let selectedModelKey: Binding<String>
    let selectedThinkingLevel: Binding<String>
    let commandSuggestionProvider: (Int) -> [CommandOption]
    let applySlashCommandSuggestion: (CommandOption) -> Void
    let focusSession: () -> Void
    let focusPermissionPrompt: () -> Void
    let answerPermission: (PermissionRequest, PermissionReply) -> Void
    let sendMessage: () -> Bool

    private var activePermission: PermissionRequest? {
        permissions.first
    }

    private var commandSuggestions: [CommandOption] {
        commandSuggestionProvider(promptCursorLocation)
    }

    private var normalizedHighlightedCommandSuggestionIndex: Int? {
        guard !commandSuggestions.isEmpty else { return nil }
        let candidate = highlightedCommandSuggestionIndex ?? 0
        return min(max(candidate, 0), commandSuggestions.count - 1)
    }

    private func applySlashCommandSuggestion(_ option: CommandOption) {
        applySlashCommandSuggestion(option)
        let updatedDraft = draft.wrappedValue
        promptCursorLocation = updatedDraft.utf16.count
        highlightedCommandSuggestionIndex = nil
    }

    private func maybeFocusPermissionPrompt(for permissionID: String?) {
        guard let permissionID else {
            lastAutoFocusedPermissionID = nil
            return
        }

        guard isFocused, lastAutoFocusedPermissionID != permissionID else { return }
        lastAutoFocusedPermissionID = permissionID
        focusPermissionPrompt()
    }

    private var permissionFocusRequestID: UUID? {
        guard activePermission != nil, isFocused else { return nil }
        return composerFocusRequestID
    }

    init(
        sessionID: String,
        permissions: [PermissionRequest],
        isFocused: Bool,
        draft: Binding<String>,
        composerFocusRequestID: UUID?,
        agentOptions: [AgentOption],
        modelOptions: [ModelOption],
        selectedModelSupportsReasoning: Bool,
        thinkingLevels: [String],
        selectedAgentKey: Binding<String>,
        selectedModelKey: Binding<String>,
        selectedThinkingLevel: Binding<String>,
        commandSuggestionProvider: @escaping (Int) -> [CommandOption],
        applySlashCommandSuggestion: @escaping (CommandOption) -> Void,
        focusSession: @escaping () -> Void,
        focusPermissionPrompt: @escaping () -> Void,
        answerPermission: @escaping (PermissionRequest, PermissionReply) -> Void,
        sendMessage: @escaping () -> Bool
    ) {
        self.sessionID = sessionID
        self.permissions = permissions
        self.isFocused = isFocused
        self.draft = draft
        self.composerFocusRequestID = composerFocusRequestID
        self.agentOptions = agentOptions
        self.modelOptions = modelOptions
        self.selectedModelSupportsReasoning = selectedModelSupportsReasoning
        self.thinkingLevels = thinkingLevels
        self.selectedAgentKey = selectedAgentKey
        self.selectedModelKey = selectedModelKey
        self.selectedThinkingLevel = selectedThinkingLevel
        self.commandSuggestionProvider = commandSuggestionProvider
        self.applySlashCommandSuggestion = applySlashCommandSuggestion
        self.focusSession = focusSession
        self.focusPermissionPrompt = focusPermissionPrompt
        self.answerPermission = answerPermission
        self.sendMessage = sendMessage
    }

    var body: some View {
        Group {
            if activePermission == nil {
                VStack(alignment: .leading, spacing: 10) {
                    PromptTextView(
                        text: draft,
                        measuredHeight: $promptHeight,
                        highlightedSuggestionIndex: $highlightedCommandSuggestionIndex,
                        cursorLocation: $promptCursorLocation,
                        suggestions: commandSuggestions,
                        suggestionAnchor: $promptSuggestionAnchor,
                        placeholder: placeholderText,
                        textColor: theme.primaryTextColor,
                        insertionPointColor: theme.primaryTextColor,
                        placeholderColor: theme.secondaryTextColor,
                        focusRequestID: composerFocusRequestID,
                        onSelectSuggestion: { option in
                            applySlashCommandSuggestion(option)
                        },
                        onFocus: {
                            focusSession()
                        },
                        onSubmit: {
                            if sendMessage() {
                                promptHeight = PromptTextView.defaultHeight
                            }
                        }
                    )
                    .frame(height: promptHeight)
                    .padding(4)

                    MacComposerAccessoryBar(
                        agentOptions: agentOptions,
                        modelOptions: modelOptions,
                        thinkingLevels: thinkingLevels,
                        selectedModelSupportsReasoning: selectedModelSupportsReasoning,
                        selectedAgentKey: selectedAgentKey,
                        selectedModelKey: selectedModelKey,
                        selectedThinkingLevel: selectedThinkingLevel
                    )
                    .padding(.leading, 0)
                    .padding(.trailing, 6)
                }
                .padding(18)
                .background {
                    SlashCommandSuggestionOverlayBridge(
                        sessionID: sessionID,
                        anchor: promptSuggestionAnchor,
                        suggestions: commandSuggestions,
                        highlightedIndex: normalizedHighlightedCommandSuggestionIndex,
                        theme: theme,
                        onSelect: { option in
                            applySlashCommandSuggestion(option)
                        }
                    )
                }
            } else if let request = activePermission {
                PermissionPromptView(
                    request: request,
                    focusRequestID: permissionFocusRequestID,
                    onReply: { reply in
                        answerPermission(request, reply)
                    }
                )
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .onAppear {
            maybeFocusPermissionPrompt(for: activePermission?.id)
        }
        .onChange(of: activePermission?.id) { _, newValue in
            maybeFocusPermissionPrompt(for: newValue)
        }
        .onChange(of: isFocused) { _, newValue in
            guard newValue else { return }
            maybeFocusPermissionPrompt(for: activePermission?.id)
        }
    }
}

private struct MacComposerAccessoryBar: View {
    let agentOptions: [AgentOption]
    let modelOptions: [ModelOption]
    let thinkingLevels: [String]
    let selectedModelSupportsReasoning: Bool
    let selectedAgentKey: Binding<String>
    let selectedModelKey: Binding<String>
    let selectedThinkingLevel: Binding<String>

    var body: some View {
        HStack(spacing: 16) {
            if !agentOptions.isEmpty {
                Picker("Agent", selection: selectedAgentKey) {
                    ForEach(agentOptions) { option in
                        Text(option.menuLabel).tag(option.id)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }

            if !modelOptions.isEmpty {
                Picker("Model", selection: selectedModelKey) {
                    ForEach(modelOptions) { option in
                        Text(option.menuLabel).tag(option.id)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)

                if selectedModelSupportsReasoning {
                    Picker("Thinking", selection: selectedThinkingLevel) {
                        ForEach(thinkingLevels, id: \.self) { level in
                            Text(level == OpenCodeAppModel.defaultThinkingLevel ? "Default" : level.capitalized).tag(level)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
            }

            Spacer(minLength: 12)
        }
    }
}

struct SuggestionListView: View {
    let theme: OpenCodeTheme
    let suggestions: [CommandOption]
    let highlightedIndex: Int?
    let onSelect: (CommandOption) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, option in
                Button {
                    onSelect(option)
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(option.name.hasPrefix("/") ? option.slashName : option.name)
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(theme.primaryText)

                        if let description = option.description, !description.isEmpty {
                            Text(description)
                                .font(.caption)
                                .foregroundStyle(theme.secondaryText)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(index == highlightedIndex ? theme.accentSubtleBackground : .clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(theme.surfaceBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(theme.border.opacity(0.7), lineWidth: 1)
        )
    }
}

typealias SlashCommandSuggestionsView = SuggestionListView

struct SlashCommandSuggestionOverlayBridge: NSViewRepresentable {
    let sessionID: String
    let anchor: CGRect
    let suggestions: [CommandOption]
    let highlightedIndex: Int?
    let theme: OpenCodeTheme
    let onSelect: (CommandOption) -> Void

    @MainActor
    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    @MainActor
    func updateNSView(_ nsView: NSView, context: Context) {
        if suggestions.isEmpty || anchor == .zero {
            SlashCommandSuggestionOverlayController.shared.dismiss(for: sessionID)
        } else {
            SlashCommandSuggestionOverlayController.shared.present(
                for: sessionID,
                anchor: anchor,
                suggestions: suggestions,
                highlightedIndex: highlightedIndex,
                theme: theme,
                onSelect: onSelect
            )
        }
    }

    @MainActor
    static func dismantleNSView(_ nsView: NSView, coordinator: ()) {
        SlashCommandSuggestionOverlayController.shared.dismissAll()
    }
}

@MainActor
private final class SlashCommandSuggestionOverlayController {
    static let shared = SlashCommandSuggestionOverlayController()

    private var panel: NSPanel?
    private var activeSessionID: String?

    func present(
        for sessionID: String,
        anchor: CGRect,
        suggestions: [CommandOption],
        highlightedIndex: Int?,
        theme: OpenCodeTheme,
        onSelect: @escaping (CommandOption) -> Void
    ) {
        guard !suggestions.isEmpty, anchor != .zero else {
            dismiss(for: sessionID)
            return
        }

        let panel = ensurePanel()
        let rowHeight: CGFloat = 34
        let height = min(CGFloat(suggestions.count) * rowHeight + 12, 220)
        let width = max(anchor.width, 360)
        let origin = CGPoint(x: anchor.minX, y: anchor.minY - height - 6)
        panel.setFrame(CGRect(origin: origin, size: CGSize(width: width, height: height)), display: true)
        panel.contentView = NSHostingView(
            rootView: SlashCommandSuggestionsView(theme: theme, suggestions: suggestions, highlightedIndex: highlightedIndex, onSelect: { option in
                onSelect(option)
                self.dismiss(for: sessionID)
            })
        )
        if panel.isVisible == false {
            panel.orderFrontRegardless()
        }
        activeSessionID = sessionID
    }

    func dismiss(for sessionID: String) {
        guard activeSessionID == sessionID else { return }
        panel?.orderOut(nil)
        activeSessionID = nil
    }

    func dismissAll() {
        panel?.orderOut(nil)
        activeSessionID = nil
    }

    private func ensurePanel() -> NSPanel {
        if let panel {
            return panel
        }

        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        self.panel = panel
        return panel
    }
}

private struct ThinkingStatusBanner: View {
    @Environment(\.openCodeTheme) private var theme
    let title: String

    @State private var visibleTitle: String
    @State private var outgoingTitle: String?
    @State private var clearOutgoingTask: Task<Void, Never>?

    init(title: String) {
        self.title = title
        _visibleTitle = State(initialValue: title)
    }

    private func attributedTitle(_ title: String) -> AttributedString {
        (try? AttributedString(markdown: title)) ?? AttributedString(title)
    }

    private func titleLabel(_ title: String) -> some View {
        Text(attributedTitle(title))
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .truncationMode(.tail)
    }

    private func shimmeringTitle(_ title: String) -> some View {
        titleLabel(title)
            .foregroundStyle(theme.secondaryText)
            .overlay {
                TimelineView(.animation) { context in
                    GeometryReader { geometry in
                        let cycle = 1.8
                        let progress = context.date.timeIntervalSinceReferenceDate
                            .truncatingRemainder(dividingBy: cycle) / cycle
                        let shimmerWidth = max(geometry.size.width * 0.5, 28)
                        let travel = geometry.size.width + shimmerWidth

                        LinearGradient(
                            colors: [
                                theme.accent.opacity(0),
                                theme.accent.opacity(0.2),
                                Color.white.opacity(0.95),
                                theme.accent.opacity(0.2),
                                theme.accent.opacity(0)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: shimmerWidth)
                        .offset(x: -shimmerWidth + (travel * progress))
                        .mask(titleLabel(title))
                    }
                }
                .allowsHitTesting(false)
            }
    }

    var body: some View {
        HStack(spacing: 0) {
            ZStack(alignment: .leading) {
                if let outgoingTitle {
                    titleLabel(outgoingTitle)
                        .foregroundStyle(theme.secondaryText)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                shimmeringTitle(visibleTitle)
                    .id(visibleTitle)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            .frame(maxWidth: .infinity, minHeight: 16, maxHeight: 16, alignment: .leading)
            .clipped()
        }
        .padding(.leading, 6)
        .padding(.trailing, 4)
        .padding(.vertical, 2)
        .animation(.easeInOut(duration: 0.22), value: visibleTitle)
        .onChange(of: title) { _, newTitle in
            guard newTitle != visibleTitle else { return }

            clearOutgoingTask?.cancel()

            let previousTitle = visibleTitle
            outgoingTitle = previousTitle

            withAnimation(.easeInOut(duration: 0.22)) {
                visibleTitle = newTitle
            }

            clearOutgoingTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(240))
                guard !Task.isCancelled else { return }
                outgoingTitle = nil
            }
        }
        .onDisappear {
            clearOutgoingTask?.cancel()
            clearOutgoingTask = nil
        }
    }
}

private struct SessionPermissionPresentationKey: Hashable {
    let sessionID: String
    let permission: String
    let patterns: [String]
    let always: [String]
    let toolMessageID: String?
    let toolCallID: String?

    init(request: PermissionRequest) {
        sessionID = request.sessionID
        permission = request.permission
        patterns = request.patterns
        always = request.always
        toolMessageID = request.tool?.messageID
        toolCallID = request.tool?.callID
    }
}

private enum TimelineMessageLayout {
    static let textLeadingInset: CGFloat = 20
    static let messageCardPadding: CGFloat = 14
    static let toolCardPadding: CGFloat = 10
    static let promptCardPadding: CGFloat = 14

    static func leadingOffset(for contentPadding: CGFloat) -> CGFloat {
        max(textLeadingInset - contentPadding, 0)
    }
}

private struct MessageRowView: View {
    @ObservedObject var messageState: SessionMessageState

    let showsTimestamp: Bool
    let availableSessions: [SessionDisplay]
    let latestTodoToolPartID: String?
    let workspaceConnection: WorkspaceConnection?
    let onInteraction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            MessageCard(
                messageState: messageState,
                showsTimestamp: showsTimestamp,
                onInteraction: onInteraction
            )

            MessageToolPartsView(
                messageState: messageState,
                availableSessions: availableSessions,
                latestTodoToolPartID: latestTodoToolPartID,
                workspaceConnection: workspaceConnection
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MessageCard: View {
    @AppStorage(ThinkingVisibilityPreferences.showsThinkingKey) private var showsThinking = true
    @Environment(\.openCodeTheme) private var theme
    @ObservedObject var messageState: SessionMessageState

    let showsTimestamp: Bool
    let onInteraction: () -> Void

    private var message: MessageEnvelope {
        messageState.snapshot
    }

    var body: some View {
        let renderDebugKey = "message-card:\(message.id)"
        let renderCount = ViewRenderDebugRegistry.recordBody(for: renderDebugKey)
        let visibleText = messageState.visibleText
        let reasoningText = messageState.reasoningText
        let showsMessageBubble = !visibleText.isEmpty
            || (showsThinking && !reasoningText.isEmpty)
            || (messageState.stepFinish?.reason?.localizedCaseInsensitiveCompare("tool-calls") != .orderedSame && messageState.stepFinish != nil)
            || messageState.info.error != nil
        let renderedMessageText = SessionTranscriptSupport.messageAttributedText(
            visibleText,
            font: .system(size: 14),
            color: theme.primaryText
        )
        let renderedReasoningText = SessionTranscriptSupport.messageAttributedText(
            reasoningText,
            font: .system(size: 13),
            color: theme.secondaryText
        )

        VStack(alignment: .leading, spacing: 8) {
            if showsTimestamp {
                TranscriptMessageHeaderView(message: message)
            }

            if showsMessageBubble {
                VStack(alignment: .leading, spacing: 10) {
                    if !visibleText.isEmpty {
                        SelectableMessageTextView(
                            attributedText: renderedMessageText
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if showsThinking, !reasoningText.isEmpty {
                        SelectableMessageTextView(
                            attributedText: renderedReasoningText
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if let finish = messageState.stepFinish, finish.reason?.localizedCaseInsensitiveCompare("tool-calls") != .orderedSame {
                        TranscriptMessageFinishView(part: finish)
                    }

                    if messageState.info.error != nil {
                        Text(messageState.info.error?.prettyDescription ?? "Unknown error")
                            .font(.caption)
                            .multilineTextAlignment(.leading)
                            .foregroundStyle(theme.error)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(TimelineMessageLayout.messageCardPadding)
                .background(bubbleBackground)
                .renderDebugBadgeOverlay(key: renderDebugKey, bodyCount: renderCount)
                .padding(.leading, TimelineMessageLayout.leadingOffset(for: TimelineMessageLayout.messageCardPadding))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var bubbleBackground: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(messageState.info.role.isAssistant ? theme.assistantBubble : theme.userBubble)
    }
}

private struct MessageToolPartsView: View {
    @ObservedObject var messageState: SessionMessageState

    let availableSessions: [SessionDisplay]
    let latestTodoToolPartID: String?
    let workspaceConnection: WorkspaceConnection?

    private var toolParts: [MessagePart] {
        messageState.toolParts
    }

    private var subagentSessionsByPartID: [String: SessionDisplay] {
        MessagePart.resolveSubagentSessions(
            for: toolParts,
            in: availableSessions,
            parentSessionID: messageState.info.sessionID,
            baseReferenceTimeMS: messageState.info.time.created
        )
    }

    var body: some View {
        ForEach(toolParts) { toolPart in
            ToolPartView(
                part: toolPart,
                subagentSession: subagentSessionsByPartID[toolPart.id],
                latestTodoToolPartID: latestTodoToolPartID,
                workspaceConnection: workspaceConnection
            )
                .padding(.leading, TimelineMessageLayout.leadingOffset(for: TimelineMessageLayout.toolCardPadding))
        }
    }
}

private struct ToolPartView: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openCodeTheme) private var theme
    let part: MessagePart
    let subagentSession: SessionDisplay?
    let latestTodoToolPartID: String?
    let workspaceConnection: WorkspaceConnection?
    @State private var isExpanded = false
    @State private var detailedPart: MessagePart?

    private var presentation: ToolPresentation {
        resolvedPart.toolPresentation
    }

    private var resolvedPart: MessagePart {
        detailedPart ?? part
    }

    private var statusLabel: String? {
        presentation.statusLabel
    }

    private var shouldAutoExpand: Bool {
        resolvedPart.isTodoWriteTool && resolvedPart.id == latestTodoToolPartID
    }

    var body: some View {
        let renderDebugKey = "tool-card:\(part.id)"
        let renderCount = ViewRenderDebugRegistry.recordBody(for: renderDebugKey)
        let cardShape = RoundedRectangle(cornerRadius: 12, style: .continuous)

        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(alignment: .center, spacing: 8) {
                    TranscriptToolSummaryView(style: presentation.summaryStyle)

                    Spacer(minLength: 8)

                    if let statusLabel {
                        Text(statusLabel)
                            .font(.caption)
                            .foregroundStyle(theme.secondaryText)
                    }

                    if let subagentSession {
                        Button {
                            guard let workspaceConnection else { return }
                            openWindow(
                                id: "session-window",
                                value: SessionWindowContext(connection: workspaceConnection, sessionID: subagentSession.id)
                            )
                        } label: {
                            Image(systemName: "arrow.up.forward.square")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(theme.accent)
                        }
                        .buttonStyle(.plain)
                        .help("Open subagent session")
                    }

                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(theme.secondaryText)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                TranscriptToolPartDrawerView(part: resolvedPart)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(10)
        .background(
            cardShape
                .fill(theme.toolCardBackground)
        )
        .clipShape(cardShape)
        .overlay(
            cardShape
                .stroke(theme.border.opacity(0.6), lineWidth: 1)
        )
        .renderDebugBadgeOverlay(key: renderDebugKey, bodyCount: renderCount)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            guard part.isTodoWriteTool else { return }
            isExpanded = shouldAutoExpand
        }
        .task(id: isExpanded) {
            guard isExpanded, part.hasDeferredDetail, detailedPart == nil else { return }
            detailedPart = await PersistenceRepository.shared.loadMessagePartDetail(partID: part.id)
        }
        .onChange(of: latestTodoToolPartID) { _, _ in
            guard part.isTodoWriteTool else { return }

            withAnimation(.easeInOut(duration: 0.18)) {
                isExpanded = shouldAutoExpand
            }
        }
    }
}

private struct PermissionPromptView: View {
    @Environment(\.openCodeTheme) private var theme

    let request: PermissionRequest
    let focusRequestID: UUID?
    let onReply: (PermissionReply) -> Void

    var body: some View {
        let renderDebugKey = "permission-card:\(request.id)"
        let renderCount = ViewRenderDebugRegistry.recordBody(for: renderDebugKey)
        VStack(alignment: .leading, spacing: 10) {
            Text("Permission Needed")
                .font(.headline)
            Text(request.permission)
                .font(.subheadline.weight(.medium))
            if !request.patterns.isEmpty {
                Text(request.patterns.joined(separator: "\n"))
                    .font(.caption.monospaced())
            }
            PermissionPromptButtonRow(
                focusRequestID: focusRequestID,
                onDeny: { onReply(.reject) },
                onAllowAlways: { onReply(.always) },
                onAllowOnce: { onReply(.once) }
            )
            .frame(height: 32)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.errorBackground)
        .renderDebugBadgeOverlay(key: renderDebugKey, bodyCount: renderCount)
    }
}

private struct PermissionPromptButtonRow: NSViewRepresentable {
    let focusRequestID: UUID?
    let onDeny: () -> Void
    let onAllowAlways: () -> Void
    let onAllowOnce: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSStackView {
        let stackView = NSStackView()
        stackView.orientation = .horizontal
        stackView.alignment = .centerY
        stackView.spacing = 8

        let denyButton = NSButton(title: "Deny", target: context.coordinator, action: #selector(Coordinator.handleDeny))
        denyButton.bezelStyle = .rounded
        denyButton.contentTintColor = .systemRed

        let allowAlwaysButton = NSButton(title: "Allow Always", target: context.coordinator, action: #selector(Coordinator.handleAllowAlways))
        allowAlwaysButton.bezelStyle = .rounded

        let allowOnceButton = NSButton(title: "Allow once", target: context.coordinator, action: #selector(Coordinator.handleAllowOnce))
        allowOnceButton.bezelStyle = .rounded
        allowOnceButton.keyEquivalent = "\r"
        allowOnceButton.keyEquivalentModifierMask = []

        stackView.addArrangedSubview(denyButton)
        stackView.addArrangedSubview(allowAlwaysButton)
        stackView.addArrangedSubview(allowOnceButton)

        context.coordinator.allowOnceButton = allowOnceButton
        context.coordinator.denyAction = onDeny
        context.coordinator.allowAlwaysAction = onAllowAlways
        context.coordinator.allowOnceAction = onAllowOnce

        return stackView
    }

    func updateNSView(_ nsView: NSStackView, context: Context) {
        context.coordinator.denyAction = onDeny
        context.coordinator.allowAlwaysAction = onAllowAlways
        context.coordinator.allowOnceAction = onAllowOnce

        guard let focusRequestID, focusRequestID != context.coordinator.lastAppliedFocusRequestID else { return }
        context.coordinator.lastAppliedFocusRequestID = focusRequestID
        context.coordinator.requestFocus()
    }

    @MainActor
    final class Coordinator: NSObject {
        var lastAppliedFocusRequestID: UUID?
        weak var allowOnceButton: NSButton?
        var denyAction: (() -> Void)?
        var allowAlwaysAction: (() -> Void)?
        var allowOnceAction: (() -> Void)?

        private var remainingFocusAttempts = 0
        private let maximumFocusAttempts = 6

        @objc
        func handleDeny() {
            denyAction?()
        }

        @objc
        func handleAllowAlways() {
            allowAlwaysAction?()
        }

        @objc
        func handleAllowOnce() {
            allowOnceAction?()
        }

        func requestFocus() {
            remainingFocusAttempts = maximumFocusAttempts
            attemptFocus()
        }

        private func attemptFocus() {
            guard remainingFocusAttempts > 0 else { return }
            remainingFocusAttempts -= 1

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if self.focusDefaultButtonIfAvailable() {
                    self.remainingFocusAttempts = 0
                    return
                }

                self.attemptFocus()
            }
        }

        private func focusDefaultButtonIfAvailable() -> Bool {
            guard let button = allowOnceButton, let window = button.window else { return false }
            window.makeFirstResponder(button)
            return window.firstResponder === button
        }
    }
}

private struct QuestionCard: View {
    let request: QuestionRequest
    let onSubmitAnswers: ([[String]]) -> Void
    let onReject: () -> Void

    var body: some View {
        let renderDebugKey = "question-card:\(request.id)"
        let renderCount = ViewRenderDebugRegistry.recordBody(for: renderDebugKey)
        TranscriptQuestionCardContent(
            request: request,
            usesCheckboxToggleStyle: true,
            leadingPadding: TimelineMessageLayout.leadingOffset(for: TimelineMessageLayout.promptCardPadding),
            onSubmitAnswers: onSubmitAnswers,
            onReject: onReject,
            trailingOverlay: {
                if DebugRuntime.isViewRenderCountersEnabled {
                    ViewRenderDebugBadge(key: renderDebugKey, bodyCount: renderCount)
                        .fixedSize()
                        .padding(8)
                } else {
                    EmptyView()
                }
            }
        )
    }
}
