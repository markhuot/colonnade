import CoreData
@preconcurrency import Foundation
import OSLog

actor PersistenceRepository {
    static let shared = PersistenceRepository()

    private enum BufferedStreamMutation {
        case upsertMessageInfo(directory: String, sessionID: String, info: MessageInfo, modelContextLimits: [ModelContextKey: Int])
        case upsertMessagePart(directory: String, sessionID: String, part: MessagePart, modelContextLimits: [ModelContextKey: Int])
        case applyMessagePartDelta(directory: String, sessionID: String, partID: String, field: MessagePartDeltaField, delta: String, modelContextLimits: [ModelContextKey: Int])
        case removeMessagePart(directory: String, sessionID: String, partID: String, modelContextLimits: [ModelContextKey: Int])
        case removeMessage(directory: String, sessionID: String, messageID: String, modelContextLimits: [ModelContextKey: Int])

        var directory: String {
            switch self {
            case let .upsertMessageInfo(directory, _, _, _),
                 let .upsertMessagePart(directory, _, _, _),
                 let .applyMessagePartDelta(directory, _, _, _, _, _),
                 let .removeMessagePart(directory, _, _, _),
                 let .removeMessage(directory, _, _, _):
                return directory
            }
        }

        var sessionID: String {
            switch self {
            case let .upsertMessageInfo(_, sessionID, _, _),
                 let .upsertMessagePart(_, sessionID, _, _),
                 let .applyMessagePartDelta(_, sessionID, _, _, _, _),
                 let .removeMessagePart(_, sessionID, _, _),
                 let .removeMessage(_, sessionID, _, _):
                return sessionID
            }
        }

        var modelContextLimits: [ModelContextKey: Int] {
            switch self {
            case let .upsertMessageInfo(_, _, _, modelContextLimits),
                 let .upsertMessagePart(_, _, _, modelContextLimits),
                 let .applyMessagePartDelta(_, _, _, _, _, modelContextLimits),
                 let .removeMessagePart(_, _, _, modelContextLimits),
                 let .removeMessage(_, _, _, modelContextLimits):
                return modelContextLimits
            }
        }

        var messageID: String? {
            switch self {
            case let .upsertMessageInfo(_, _, info, _):
                return info.id
            case let .upsertMessagePart(_, _, part, _):
                return part.messageID
            case .applyMessagePartDelta, .removeMessagePart:
                return nil
            case let .removeMessage(_, _, messageID, _):
                return messageID
            }
        }

        var partID: String? {
            switch self {
            case .upsertMessageInfo, .removeMessage:
                return nil
            case let .upsertMessagePart(_, _, part, _):
                return part.id
            case let .applyMessagePartDelta(_, _, partID, _, _, _),
                 let .removeMessagePart(_, _, partID, _):
                return partID
            }
        }

        func merged(with next: BufferedStreamMutation) -> BufferedStreamMutation? {
            switch (self, next) {
            case let (
                .upsertMessageInfo(directory: lhsDirectory, sessionID: lhsSessionID, info: lhsInfo, modelContextLimits: _),
                .upsertMessageInfo(directory: rhsDirectory, sessionID: rhsSessionID, info: rhsInfo, modelContextLimits: rhsLimits)
            ) where lhsDirectory == rhsDirectory && lhsSessionID == rhsSessionID && lhsInfo.id == rhsInfo.id:
                return .upsertMessageInfo(
                    directory: lhsDirectory,
                    sessionID: lhsSessionID,
                    info: rhsInfo,
                    modelContextLimits: rhsLimits
                )
            case let (
                .applyMessagePartDelta(directory: lhsDirectory, sessionID: lhsSessionID, partID: lhsPartID, field: lhsField, delta: lhsDelta, modelContextLimits: _),
                .applyMessagePartDelta(directory: rhsDirectory, sessionID: rhsSessionID, partID: rhsPartID, field: rhsField, delta: rhsDelta, modelContextLimits: rhsLimits)
            ) where lhsDirectory == rhsDirectory && lhsSessionID == rhsSessionID && lhsPartID == rhsPartID && lhsField == rhsField:
                return .applyMessagePartDelta(
                    directory: lhsDirectory,
                    sessionID: lhsSessionID,
                    partID: lhsPartID,
                    field: lhsField,
                    delta: lhsDelta + rhsDelta,
                    modelContextLimits: rhsLimits
                )
            default:
                return nil
            }
        }
    }

    private final class StreamMutationBuffer: @unchecked Sendable {
        private let persistence: PersistenceController
        private let logger = Logger(subsystem: "ai.opencode.app", category: "persistence")
        private let flushInterval = Duration.seconds(1)
        private let lock = NSLock()

        private var bufferedStreamMutations: [BufferedStreamMutation] = []
        private var bufferedStreamFlushTask: Task<Void, Never>?
        private var activeFlushTask: Task<Void, Never>?

        init(persistence: PersistenceController) {
            self.persistence = persistence
        }

        func enqueue(_ mutation: BufferedStreamMutation) {
            lock.lock()
            defer { lock.unlock() }

            var mutation = mutation
            var index = bufferedStreamMutations.count - 1

            while index >= 0 {
                let existing = bufferedStreamMutations[index]

                guard existing.directory == mutation.directory, existing.sessionID == mutation.sessionID else {
                    index -= 1
                    continue
                }

                if let mergedMutation = existing.merged(with: mutation) {
                    bufferedStreamMutations[index] = mergedMutation
                    scheduleBufferedStreamFlushLocked()
                    return
                }

                switch (existing, mutation) {
                case let (.upsertMessagePart(directory, sessionID, part, _), .applyMessagePartDelta(_, _, partID, field, delta, modelContextLimits))
                    where part.id == partID:
                    var updatedPart = part
                    updatedPart.apply(delta: delta, to: field)
                    mutation = .upsertMessagePart(
                        directory: directory,
                        sessionID: sessionID,
                        part: updatedPart,
                        modelContextLimits: modelContextLimits
                    )
                    bufferedStreamMutations[index] = mutation
                    scheduleBufferedStreamFlushLocked()
                    return

                case let (.applyMessagePartDelta(_, _, partID, field, delta, _), .upsertMessagePart(directory, sessionID, part, modelContextLimits))
                    where part.id == partID:
                    var updatedPart = part
                    updatedPart.apply(delta: delta, to: field)
                    mutation = .upsertMessagePart(
                        directory: directory,
                        sessionID: sessionID,
                        part: updatedPart,
                        modelContextLimits: modelContextLimits
                    )
                    bufferedStreamMutations.remove(at: index)

                case let (.upsertMessagePart(_, _, part, _), .upsertMessagePart(directory, sessionID, newPart, modelContextLimits))
                    where part.id == newPart.id:
                    mutation = .upsertMessagePart(
                        directory: directory,
                        sessionID: sessionID,
                        part: newPart,
                        modelContextLimits: modelContextLimits
                    )
                    bufferedStreamMutations[index] = mutation
                    scheduleBufferedStreamFlushLocked()
                    return

                case let (.upsertMessageInfo(_, _, info, _), .upsertMessageInfo(directory, sessionID, newInfo, modelContextLimits))
                    where info.id == newInfo.id:
                    mutation = .upsertMessageInfo(
                        directory: directory,
                        sessionID: sessionID,
                        info: newInfo,
                        modelContextLimits: modelContextLimits
                    )
                    bufferedStreamMutations[index] = mutation
                    scheduleBufferedStreamFlushLocked()
                    return

                case let (_, .removeMessagePart(_, _, partID, _))
                    where existing.partID == partID:
                    bufferedStreamMutations.remove(at: index)

                default:
                    break
                }

                index -= 1
            }

            bufferedStreamMutations.append(mutation)
            scheduleBufferedStreamFlushLocked()
        }

        func flushIfNeeded() async {
            while let task = startFlushIfNeeded(cancelScheduledTask: true) {
                await task.value
            }
        }

        private func scheduleBufferedStreamFlushLocked() {
            guard bufferedStreamFlushTask == nil else { return }

            let flushInterval = flushInterval
            bufferedStreamFlushTask = Task { [self] in
                try? await Task.sleep(for: flushInterval)
                await flushIfNeeded()
            }
        }

        private func startFlushIfNeeded(cancelScheduledTask: Bool) -> Task<Void, Never>? {
            lock.lock()
            defer { lock.unlock() }

            if cancelScheduledTask {
                bufferedStreamFlushTask?.cancel()
                bufferedStreamFlushTask = nil
            }

            if let activeFlushTask {
                return activeFlushTask
            }

            guard !bufferedStreamMutations.isEmpty else {
                return nil
            }

            let mutations = bufferedStreamMutations
            bufferedStreamMutations.removeAll(keepingCapacity: true)

            let flushTask = Task { [self, mutations] in
                let saveSucceeded = flush(mutations)
                finishFlush(mutations: mutations, saveSucceeded: saveSucceeded)
            }
            activeFlushTask = flushTask
            return flushTask
        }

        private func finishFlush(mutations: [BufferedStreamMutation], saveSucceeded: Bool) {
            lock.lock()
            activeFlushTask = nil

            if !saveSucceeded {
                bufferedStreamMutations.insert(contentsOf: mutations, at: 0)
            }

            let shouldScheduleFlush = !bufferedStreamMutations.isEmpty && bufferedStreamFlushTask == nil
            lock.unlock()

            if shouldScheduleFlush {
                lock.lock()
                scheduleBufferedStreamFlushLocked()
                lock.unlock()
            }
        }

        private func flush(_ mutations: [BufferedStreamMutation]) -> Bool {
            let streamWriteContext = persistence.newBackgroundContext()
            return Self.performSync(on: streamWriteContext) { streamWriteContext in
                var workspaceIDs: [String: String] = [:]
                var affectedSessionIDsByDirectory: [String: Set<String>] = [:]
                var latestModelContextLimitsByDirectory: [String: [ModelContextKey: Int]] = [:]

                for mutation in mutations {
                    let directory = mutation.directory
                    let workspace = PersistenceRepository.findOrCreateWorkspace(directory: directory, context: streamWriteContext)
                    let workspaceID = workspace.id ?? directory
                    workspace.projectName = (directory as NSString).lastPathComponent
                    workspaceIDs[directory] = workspaceID
                    affectedSessionIDsByDirectory[directory, default: []].insert(mutation.sessionID)
                    latestModelContextLimitsByDirectory[directory] = mutation.modelContextLimits

                    switch mutation {
                    case let .upsertMessageInfo(_, sessionID, info, _):
                        PersistenceRepository.upsertMessageInfo(info, sessionID: sessionID, context: streamWriteContext)
                    case let .upsertMessagePart(_, sessionID, part, _):
                        PersistenceRepository.upsertMessagePart(part, sessionID: sessionID, context: streamWriteContext)
                    case let .applyMessagePartDelta(_, _, partID, field, delta, _):
                        PersistenceRepository.applyMessagePartDelta(partID: partID, field: field, delta: delta, context: streamWriteContext)
                    case let .removeMessagePart(_, _, partID, _):
                        PersistenceRepository.removeMessagePart(partID: partID, context: streamWriteContext)
                    case let .removeMessage(_, _, messageID, _):
                        PersistenceRepository.removeMessage(messageID: messageID, context: streamWriteContext)
                    }
                }

                for (directory, sessionIDs) in affectedSessionIDsByDirectory {
                    guard let workspaceID = workspaceIDs[directory] else { continue }
                    PersistenceRepository.recomputeSessionDerivedState(
                        workspaceID: workspaceID,
                        modelContextLimits: latestModelContextLimitsByDirectory[directory] ?? [:],
                        context: streamWriteContext,
                        sessionIDs: Array(sessionIDs)
                    )
                }

                do {
                    if streamWriteContext.hasChanges {
                        try streamWriteContext.save()
                    }
                    streamWriteContext.reset()
                    return true
                } catch {
                    self.logger.error("Buffered stream mutation flush failed: \(error.localizedDescription, privacy: .public)")
                    streamWriteContext.rollback()
                    return false
                }
            }
        }

        private static func performSync<T>(on context: NSManagedObjectContext, _ work: @Sendable (NSManagedObjectContext) -> T) -> T {
            context.performAndWait {
                work(context)
            }
        }
    }

    private let persistence: PersistenceController
    private let logger = Logger(subsystem: "ai.opencode.app", category: "persistence")
    private let streamMutationBuffer: StreamMutationBuffer

    init(persistence: PersistenceController = .shared) {
        self.persistence = persistence
        streamMutationBuffer = StreamMutationBuffer(persistence: persistence)
    }

    nonisolated private static let logger = Logger(subsystem: "ai.opencode.app", category: "persistence")

    nonisolated private static func performSync<T>(on context: NSManagedObjectContext, _ work: @Sendable (NSManagedObjectContext) -> T) -> T {
        context.performAndWait {
            work(context)
        }
    }

    func loadSnapshot(directory: String?) async -> PersistenceSnapshot {
        await flushBufferedStreamMutationsIfNeeded()
        let context = persistence.newBackgroundContext()
        let startedAt = ContinuousClock.now
        let snapshot = Self.performSync(on: context) { context in
            Self.makeSnapshot(context: context, directory: directory)
        }
        let duration = startedAt.duration(to: .now)

        let openMessageCount = snapshot.messagesBySession.values.reduce(0) { $0 + $1.count }
        logger.notice(
            "Loaded snapshot directory=\((directory ?? snapshot.selectedDirectory ?? "nil"), privacy: .public) sessions=\(snapshot.sessions.count, privacy: .public) messageSessions=\(snapshot.messagesBySession.count, privacy: .public) messages=\(openMessageCount, privacy: .public) durationMS=\(duration.milliseconds, privacy: .public)"
        )
        return snapshot
    }

    func loadLastSelectedDirectory() async -> String? {
        await flushBufferedStreamMutationsIfNeeded()
        let context = persistence.newBackgroundContext()
        return Self.performSync(on: context) { context in
            let request = WorkspaceEntity.fetchRequest()
            request.fetchLimit = 1
            request.predicate = NSPredicate(format: "isSelected == YES")
            let workspace = try? context.fetch(request).first
            return workspace?.directory
        }
    }

    func selectWorkspace(directory: String) async {
        await flushBufferedStreamMutationsIfNeeded()
        let context = persistence.newBackgroundContext()
        Self.performSync(on: context) { context in
            let request = WorkspaceEntity.fetchRequest()
            if let workspaces = try? context.fetch(request) {
                for workspace in workspaces {
                    workspace.isSelected = NSNumber(value: workspace.directory == directory)
                }
            }

            let workspace = Self.findOrCreateWorkspace(directory: directory, context: context)
            workspace.isSelected = true
            workspace.projectName = (directory as NSString).lastPathComponent
            try? context.save()
        }
    }

    func savePanes(directory: String, panes: [SessionPaneState]) async {
        await flushBufferedStreamMutationsIfNeeded()
        let context = persistence.newBackgroundContext()
        Self.performSync(on: context) { context in
            let workspace = Self.findOrCreateWorkspace(directory: directory, context: context)
            let workspaceID = workspace.id ?? directory

            let request = SessionPaneEntity.fetchRequest()
            request.predicate = NSPredicate(format: "workspaceID == %@", workspaceID)
            if let existing = try? context.fetch(request) {
                existing.forEach(context.delete)
            }

            for pane in panes {
                let entity: SessionPaneEntity = Self.insertEntity(in: context)
                entity.id = "\(workspaceID)::\(pane.sessionID)"
                entity.workspaceID = workspaceID
                entity.sessionID = pane.sessionID
                entity.position = NSNumber(value: pane.position)
                entity.width = NSNumber(value: pane.width)
                entity.isHidden = NSNumber(value: pane.isHidden)
            }

            try? context.save()
        }
    }

    func applyWorkspaceSnapshot(
        directory: String,
        snapshot: WorkspaceSnapshot,
        modelContextLimits: [ModelContextKey: Int],
        openSessionIDs: [String]
    ) async {
        await flushBufferedStreamMutationsIfNeeded()
        logger.notice(
            "Applying workspace snapshot directory=\(directory, privacy: .public) sessions=\(snapshot.sessions.count, privacy: .public) statuses=\(snapshot.statuses.count, privacy: .public) openSessions=\(openSessionIDs.count, privacy: .public)"
        )
        let context = persistence.newBackgroundContext()
        Self.performSync(on: context) { context in
            let workspace = Self.findOrCreateWorkspace(directory: directory, context: context)
            let workspaceID = workspace.id ?? directory
            let existingSessionRequest = SessionEntity.fetchRequest()
            existingSessionRequest.predicate = NSPredicate(format: "workspaceID == %@", workspaceID)
            let existingSessions = (try? context.fetch(existingSessionRequest)) ?? []

            if snapshot.sessions.isEmpty, !existingSessions.isEmpty {
                self.logger.notice(
                    "Ignoring empty workspace snapshot directory=\(directory, privacy: .public) existingSessions=\(existingSessions.count, privacy: .public) openSessions=\(openSessionIDs.count, privacy: .public)"
                )
                return
            }

            workspace.projectName = (directory as NSString).lastPathComponent
            workspace.lastSyncedAt = Date()

            Self.pruneMissingSessions(snapshot.sessions.map(\.id), workspaceID: workspaceID, context: context)
            Self.upsertSessions(snapshot.sessions, workspaceID: workspaceID, context: context)
            Self.replaceStatuses(snapshot.statuses, workspaceID: workspaceID, context: context)
            Self.replaceQuestions(snapshot.questions, workspaceID: workspaceID, context: context)
            Self.replacePermissions(snapshot.permissions, workspaceID: workspaceID, context: context)
            Self.recomputeSessionDerivedState(workspaceID: workspaceID, modelContextLimits: modelContextLimits, context: context)
            try? context.save()
        }
        logger.notice("Applied workspace snapshot directory=\(directory, privacy: .public)")
    }

    func replaceSessions(directory: String, sessions: [OpenCodeSession], modelContextLimits: [ModelContextKey: Int]) async {
        await flushBufferedStreamMutationsIfNeeded()
        let context = persistence.newBackgroundContext()
        Self.performSync(on: context) { context in
            let workspace = Self.findOrCreateWorkspace(directory: directory, context: context)
            let workspaceID = workspace.id ?? directory
            Self.pruneMissingSessions(sessions.map(\.id), workspaceID: workspaceID, context: context)
            Self.upsertSessions(sessions, workspaceID: workspaceID, context: context)
            Self.recomputeSessionDerivedState(workspaceID: workspaceID, modelContextLimits: modelContextLimits, context: context)
            try? context.save()
        }
    }

    func replaceMessages(directory: String, sessionID: String, messages: [MessageEnvelope], modelContextLimits: [ModelContextKey: Int]) async {
        await flushBufferedStreamMutationsIfNeeded()
        let partCount = messages.reduce(0) { $0 + $1.parts.count }
        let lastMessageID = messages.last?.id ?? "nil"
        logger.notice(
            "Replacing messages sessionID=\(sessionID, privacy: .public) count=\(messages.count, privacy: .public) parts=\(partCount, privacy: .public) lastMessageID=\(lastMessageID, privacy: .public)"
        )
        let context = persistence.newBackgroundContext()
        Self.performSync(on: context) { context in
            let workspace = Self.findOrCreateWorkspace(directory: directory, context: context)
            let workspaceID = workspace.id ?? directory
            Self.replaceMessages(messages, sessionID: sessionID, context: context)
            Self.recomputeSessionDerivedState(workspaceID: workspaceID, modelContextLimits: modelContextLimits, context: context, sessionIDs: [sessionID])
            try? context.save()
        }
        logger.notice(
            "Replaced messages sessionID=\(sessionID, privacy: .public) count=\(messages.count, privacy: .public) parts=\(partCount, privacy: .public)"
        )
    }

    func replaceTodos(directory: String, sessionID: String, todos: [SessionTodo], modelContextLimits: [ModelContextKey: Int]) async {
        await flushBufferedStreamMutationsIfNeeded()
        let context = persistence.newBackgroundContext()
        Self.performSync(on: context) { context in
            let workspace = Self.findOrCreateWorkspace(directory: directory, context: context)
            let workspaceID = workspace.id ?? directory
            Self.replaceTodos(todos, sessionID: sessionID, context: context)
            Self.recomputeSessionDerivedState(workspaceID: workspaceID, modelContextLimits: modelContextLimits, context: context, sessionIDs: [sessionID])
            try? context.save()
        }
    }

    func applySessionLifecycle(directory: String, session: OpenCodeSession, lifecycle: SessionLifecycleEvent, modelContextLimits: [ModelContextKey: Int]) async {
        await flushBufferedStreamMutationsIfNeeded()
        let context = persistence.newBackgroundContext()
        Self.performSync(on: context) { context in
            let workspace = Self.findOrCreateWorkspace(directory: directory, context: context)
            let workspaceID = workspace.id ?? directory

            switch lifecycle {
            case .created, .updated:
                Self.upsertSessions([session], workspaceID: workspaceID, context: context)
            case .deleted:
                let request = SessionEntity.fetchRequest()
                request.predicate = NSPredicate(format: "id == %@", session.id)
                if let target = try? context.fetch(request).first {
                    context.delete(target)
                }
            }

            Self.recomputeSessionDerivedState(workspaceID: workspaceID, modelContextLimits: modelContextLimits, context: context, sessionIDs: [session.id])
            try? context.save()
        }
    }

    func applyStatus(directory: String, sessionID: String, status: SessionStatus?, modelContextLimits: [ModelContextKey: Int]) async {
        await flushBufferedStreamMutationsIfNeeded()
        let context = persistence.newBackgroundContext()
        Self.performSync(on: context) { context in
            let workspace = Self.findOrCreateWorkspace(directory: directory, context: context)
            let workspaceID = workspace.id ?? directory
            if let status {
                Self.setStatus(status, for: sessionID, workspaceID: workspaceID, context: context)
            } else {
                Self.clearStatus(for: sessionID, workspaceID: workspaceID, context: context)
            }
            Self.recomputeSessionDerivedState(workspaceID: workspaceID, modelContextLimits: modelContextLimits, context: context, sessionIDs: [sessionID])
            try? context.save()
        }
    }

    func replaceStatuses(directory: String, statuses: [String: SessionStatus], modelContextLimits: [ModelContextKey: Int]) async {
        await flushBufferedStreamMutationsIfNeeded()
        let context = persistence.newBackgroundContext()
        Self.performSync(on: context) { context in
            let workspace = Self.findOrCreateWorkspace(directory: directory, context: context)
            let workspaceID = workspace.id ?? directory
            Self.replaceStatuses(statuses, workspaceID: workspaceID, context: context)
            Self.recomputeSessionDerivedState(workspaceID: workspaceID, modelContextLimits: modelContextLimits, context: context)
            try? context.save()
        }
    }

    func replaceInteractions(directory: String, snapshot: InteractionSnapshot, modelContextLimits: [ModelContextKey: Int]) async {
        await flushBufferedStreamMutationsIfNeeded()
        let context = persistence.newBackgroundContext()
        Self.performSync(on: context) { context in
            let workspace = Self.findOrCreateWorkspace(directory: directory, context: context)
            let workspaceID = workspace.id ?? directory
            Self.replaceQuestions(snapshot.questions, workspaceID: workspaceID, context: context)
            Self.replacePermissions(snapshot.permissions, workspaceID: workspaceID, context: context)
            Self.recomputeSessionDerivedState(workspaceID: workspaceID, modelContextLimits: modelContextLimits, context: context)
            try? context.save()
        }
    }

    nonisolated func upsertMessagePart(directory: String, sessionID: String, part: MessagePart, modelContextLimits: [ModelContextKey: Int]) async {
        streamMutationBuffer.enqueue(
            .upsertMessagePart(
                directory: directory,
                sessionID: sessionID,
                part: part,
                modelContextLimits: modelContextLimits
            )
        )
    }

    nonisolated func upsertMessageInfo(directory: String, sessionID: String, info: MessageInfo, modelContextLimits: [ModelContextKey: Int]) async {
        streamMutationBuffer.enqueue(
            .upsertMessageInfo(
                directory: directory,
                sessionID: sessionID,
                info: info,
                modelContextLimits: modelContextLimits
            )
        )
    }

    nonisolated func applyMessagePartDelta(directory: String, sessionID: String, partID: String, field: MessagePartDeltaField, delta: String, modelContextLimits: [ModelContextKey: Int]) async {
        streamMutationBuffer.enqueue(
            .applyMessagePartDelta(
                directory: directory,
                sessionID: sessionID,
                partID: partID,
                field: field,
                delta: delta,
                modelContextLimits: modelContextLimits
            )
        )
    }

    nonisolated func removeMessagePart(directory: String, sessionID: String, partID: String, modelContextLimits: [ModelContextKey: Int]) async {
        streamMutationBuffer.enqueue(
            .removeMessagePart(
                directory: directory,
                sessionID: sessionID,
                partID: partID,
                modelContextLimits: modelContextLimits
            )
        )
    }

    nonisolated func removeMessage(directory: String, sessionID: String, messageID: String, modelContextLimits: [ModelContextKey: Int]) async {
        streamMutationBuffer.enqueue(
            .removeMessage(
                directory: directory,
                sessionID: sessionID,
                messageID: messageID,
                modelContextLimits: modelContextLimits
            )
        )
    }

    nonisolated func flushBufferedStreamMutations() async {
        await streamMutationBuffer.flushIfNeeded()
    }

    private func flushBufferedStreamMutationsIfNeeded() async {
        await streamMutationBuffer.flushIfNeeded()
    }

    private static func makeSnapshot(context: NSManagedObjectContext, directory: String?) -> PersistenceSnapshot {
        let workspaceRequest = WorkspaceEntity.fetchRequest()
        if let directory {
            workspaceRequest.predicate = NSPredicate(format: "directory == %@", directory)
        } else {
            workspaceRequest.predicate = NSPredicate(format: "isSelected == YES")
        }
        workspaceRequest.fetchLimit = 1

        guard let workspace = try? context.fetch(workspaceRequest).first,
              let workspaceID = workspace.id else {
            return .empty
        }

        let sessionRequest = SessionEntity.fetchRequest()
        sessionRequest.predicate = NSPredicate(format: "workspaceID == %@", workspaceID)
        sessionRequest.sortDescriptors = [NSSortDescriptor(key: "sortUpdatedAtMS", ascending: false)]
        let sessionEntities = (try? context.fetch(sessionRequest)) ?? []
        let sessions = sessionEntities.compactMap(Self.makeSessionDisplay)

        let messageRequest = MessageEntity.fetchRequest()
        messageRequest.predicate = NSPredicate(format: "sessionID IN %@", sessions.map(\.id))
        messageRequest.sortDescriptors = [
            NSSortDescriptor(key: "sessionID", ascending: true),
            NSSortDescriptor(key: "createdAtMS", ascending: true)
        ]
        let messageEntities = (try? context.fetch(messageRequest)) ?? []

        let partRequest = MessagePartEntity.fetchRequest()
        partRequest.predicate = NSPredicate(format: "sessionID IN %@", sessions.map(\.id))
        let partEntities = (try? context.fetch(partRequest)) ?? []
        let partsByMessageID = Dictionary(grouping: partEntities, by: { $0.messageID ?? "" })

        let messagesBySession = Dictionary(grouping: messageEntities.compactMap { entity -> (String, MessageEnvelope)? in
            guard let sessionID = entity.sessionID,
                  let message = decodeMessage(entity, partsByMessageID: partsByMessageID) else { return nil }
            return (sessionID, message)
        }, by: \.0).mapValues { items in
            items.map(\.1)
        }

        let questionRequest = QuestionEntity.fetchRequest()
        questionRequest.predicate = NSPredicate(format: "workspaceID == %@", workspaceID)
        let questions = ((try? context.fetch(questionRequest)) ?? []).compactMap { entity -> (String, QuestionRequest)? in
            guard let sessionID = entity.sessionID,
                  let question = PersistenceCoders.decode(QuestionRequest.self, from: entity.payloadJSON) else { return nil }
            return (sessionID, question)
        }

        let permissionRequest = PermissionEntity.fetchRequest()
        permissionRequest.predicate = NSPredicate(format: "workspaceID == %@", workspaceID)
        let permissions = ((try? context.fetch(permissionRequest)) ?? []).compactMap { entity -> (String, PermissionRequest)? in
            guard let sessionID = entity.sessionID,
                  let permission = PersistenceCoders.decode(PermissionRequest.self, from: entity.payloadJSON) else { return nil }
            return (sessionID, permission)
        }

        let paneRequest = SessionPaneEntity.fetchRequest()
        paneRequest.predicate = NSPredicate(format: "workspaceID == %@", workspaceID)
        let panes = ((try? context.fetch(paneRequest)) ?? []).reduce(into: [String: SessionPaneState]()) { result, entity in
            guard let sessionID = entity.sessionID else { return }
            result[sessionID] = SessionPaneState(
                sessionID: sessionID,
                position: entity.position?.intValue ?? 0,
                width: entity.width?.doubleValue ?? 520,
                isHidden: entity.isHidden?.boolValue ?? false
            )
        }

        let snapshot = PersistenceSnapshot(
            sessions: sessions,
            messagesBySession: messagesBySession,
            questionsBySession: Dictionary(grouping: questions, by: \.0).mapValues { $0.map(\.1) },
            permissionsBySession: Dictionary(grouping: permissions, by: \.0).mapValues { $0.map(\.1) },
            selectedDirectory: workspace.directory,
            paneStates: panes
        )

        return snapshot
    }

    private static func makeSessionDisplay(_ entity: SessionEntity) -> SessionDisplay? {
        guard let id = entity.id else { return nil }
        let todoTotal = entity.todoTotalCount?.intValue ?? 0
        let todoActionable = entity.todoActionableCount?.intValue ?? 0
        let todoCompleted = entity.todoCompletedCount?.intValue ?? 0
        let todoProgress = todoTotal > 0 && todoActionable > 0
            ? TodoProgress(completed: todoCompleted, total: todoTotal, actionable: todoActionable)
            : nil

        let percent = entity.lastContextUsagePercent?.intValue
        return SessionDisplay(
            id: id,
            title: entity.title ?? id,
            createdAtMS: entity.createdAtMS?.doubleValue ?? 0,
            updatedAtMS: entity.sortUpdatedAtMS?.doubleValue ?? entity.updatedAtMS?.doubleValue ?? 0,
            parentID: entity.parentID,
            status: decodeStatus(entity),
            hasPendingPermission: entity.hasPendingPermission?.boolValue ?? false,
            todoProgress: todoProgress,
            contextUsageText: percent.map { "\($0)% used" },
            isArchived: entity.archivedAtMS?.doubleValue != nil
        )
    }

    private static func decodeStatus(_ entity: SessionEntity) -> SessionStatus? {
        guard let type = entity.statusType else { return nil }
        switch type {
        case "idle":
            return .idle
        case "busy":
            return .busy
        case "retry":
            return .retry(
                attempt: entity.statusAttempt?.intValue ?? 0,
                message: entity.statusLabel ?? "Retrying",
                next: entity.statusNextMS?.doubleValue ?? 0
            )
        default:
            return .unknown(type)
        }
    }

    private static func decodeMessage(_ entity: MessageEntity, partsByMessageID: [String: [MessagePartEntity]]) -> MessageEnvelope? {
        guard let id = entity.id,
              let sessionID = entity.sessionID,
              let roleRaw = entity.roleRaw else { return nil }

        let fallbackInfo = MessageInfo(
            id: id,
            sessionID: sessionID,
            role: MessageRole(rawString: roleRaw),
            time: .init(created: entity.createdAtMS?.doubleValue ?? 0, completed: entity.completedAtMS?.doubleValue),
            parentID: entity.parentID,
            agent: entity.agent,
            model: (entity.modelProviderID != nil && entity.modelID != nil) ? .init(providerID: entity.modelProviderID!, modelID: entity.modelID!) : nil,
            modelID: entity.modelID,
            providerID: entity.modelProviderID,
            mode: entity.mode,
            path: (entity.pathCwd != nil && entity.pathRoot != nil) ? .init(cwd: entity.pathCwd!, root: entity.pathRoot!) : nil,
            cost: entity.cost?.doubleValue,
            tokens: .init(
                total: entity.tokenTotal?.intValue,
                input: entity.tokenInput?.intValue,
                output: entity.tokenOutput?.intValue,
                reasoning: entity.tokenReasoning?.intValue,
                cache: .init(read: entity.tokenCacheRead?.intValue, write: entity.tokenCacheWrite?.intValue)
            ),
            finish: entity.finish,
            summary: PersistenceCoders.decode(JSONValue.self, from: entity.summaryJSON),
            error: PersistenceCoders.decode(JSONValue.self, from: entity.errorJSON)
        )

        let info: MessageInfo
        let decodedParts: [MessagePart]

        if let decoded = PersistenceCoders.decode(MessageEnvelope.self, from: entity.payloadJSON) {
            var decodedInfo = decoded.info

            if decodedInfo.model == nil, let model = fallbackInfo.model {
                decodedInfo = MessageInfo(
                    id: decodedInfo.id,
                    sessionID: decodedInfo.sessionID,
                    role: decodedInfo.role,
                    time: decodedInfo.time,
                    parentID: decodedInfo.parentID,
                    agent: decodedInfo.agent,
                    model: model,
                    modelID: fallbackInfo.modelID,
                    providerID: fallbackInfo.providerID,
                    mode: decodedInfo.mode,
                    path: decodedInfo.path,
                    cost: decodedInfo.cost,
                    tokens: decodedInfo.tokens,
                    finish: decodedInfo.finish,
                    summary: decodedInfo.summary,
                    error: decodedInfo.error
                )
            }

            info = decodedInfo
            decodedParts = decoded.parts
        } else {
            info = fallbackInfo
            decodedParts = []
        }

        let parts = (partsByMessageID[id] ?? []).compactMap(decodePart).sorted {
            ($0.time?.start ?? 0) < ($1.time?.start ?? 0)
        }

        return MessageEnvelope(info: info, parts: parts.isEmpty ? decodedParts : parts)
    }

    private static func decodePart(_ entity: MessagePartEntity) -> MessagePart? {
        if let decoded = PersistenceCoders.decode(MessagePart.self, from: entity.payloadJSON) {
            return decoded
        }

        guard let id = entity.id, let typeRaw = entity.typeRaw else { return nil }
        return MessagePart(
            id: id,
            sessionID: entity.sessionID,
            messageID: entity.messageID,
            type: MessagePartKind(rawString: typeRaw),
            text: entity.text,
            synthetic: entity.synthetic?.boolValue,
            ignored: entity.ignored?.boolValue,
            time: .init(start: entity.startAtMS?.doubleValue, end: entity.endAtMS?.doubleValue, compacted: entity.compactedAtMS?.doubleValue),
            metadata: PersistenceCoders.decode([String: JSONValue].self, from: entity.metadataJSON),
            callID: entity.callID,
            tool: entity.tool,
            state: decodeToolState(entity),
            mime: entity.mime,
            filename: entity.filename,
            url: entity.url,
            reason: entity.reason,
            cost: entity.cost?.doubleValue,
            tokens: .init(
                total: entity.tokenTotal?.intValue,
                input: entity.tokenInput?.intValue,
                output: entity.tokenOutput?.intValue,
                reasoning: entity.tokenReasoning?.intValue,
                cache: .init(read: entity.tokenCacheRead?.intValue, write: entity.tokenCacheWrite?.intValue)
            ),
            prompt: entity.prompt,
            description: entity.partDescription,
            agent: entity.agent,
            model: (entity.modelProviderID != nil && entity.modelID != nil) ? .init(providerID: entity.modelProviderID!, modelID: entity.modelID!) : nil,
            command: entity.command,
            name: entity.name,
            source: (entity.sourceValue != nil) ? .init(value: entity.sourceValue!, start: entity.sourceStart?.intValue ?? 0, end: entity.sourceEnd?.intValue ?? 0) : nil,
            hash: entity.hashString,
            files: PersistenceCoders.decode([String].self, from: entity.filesJSON),
            snapshot: entity.snapshot
        )
    }

    private static func decodeToolState(_ entity: MessagePartEntity) -> MessagePart.ToolState? {
        guard let status = entity.stateStatus else { return nil }
        return .init(
            status: ToolExecutionStatus(rawString: status),
            input: PersistenceCoders.decode([String: JSONValue].self, from: entity.stateInputJSON),
            raw: entity.stateRaw,
            output: entity.stateOutput,
            title: entity.stateTitle,
            metadata: PersistenceCoders.decode([String: JSONValue].self, from: entity.stateMetadataJSON),
            error: entity.stateError,
            time: nil,
            attachments: PersistenceCoders.decode([MessagePart.FileAttachment].self, from: entity.stateAttachmentsJSON)
        )
    }

    private static func findOrCreateWorkspace(directory: String, context: NSManagedObjectContext) -> WorkspaceEntity {
        let request = WorkspaceEntity.fetchRequest()
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "directory == %@", directory)

        if let existing = try? context.fetch(request).first {
            return existing
        }

        let workspace: WorkspaceEntity = insertEntity(in: context)
        workspace.id = directory
        workspace.directory = directory
        workspace.projectName = (directory as NSString).lastPathComponent
        workspace.isSelected = false
        return workspace
    }

    private static func upsertSessions(_ sessions: [OpenCodeSession], workspaceID: String, context: NSManagedObjectContext) {
        let existing = fetchByID(SessionEntity.self, ids: sessions.map(\.id), context: context)
        for session in sessions {
            let entity = existing[session.id] ?? insertEntity(in: context)
            entity.id = session.id
            entity.workspaceID = workspaceID
            entity.payloadJSON = PersistenceCoders.encode(session)
            entity.slug = session.slug
            entity.projectID = session.projectID
            entity.workspaceRefID = session.workspaceID
            entity.directory = session.directory
            entity.parentID = session.parentID
            entity.title = session.title
            entity.version = session.version
            entity.createdAtMS = NSNumber(value: session.time.created)
            entity.updatedAtMS = NSNumber(value: session.time.updated)
            entity.compactingAtMS = session.time.compacting.map(NSNumber.init(value:))
            entity.archivedAtMS = session.time.archived.map(NSNumber.init(value:))
            entity.summaryAdditions = session.summary?.additions.map(NSNumber.init(value:))
            entity.summaryDeletions = session.summary?.deletions.map(NSNumber.init(value:))
            entity.summaryFiles = session.summary?.files.map(NSNumber.init(value:))
            entity.sortUpdatedAtMS = NSNumber(value: session.time.updated)
        }
    }

    private static func pruneMissingSessions(_ sessionIDs: [String], workspaceID: String, context: NSManagedObjectContext) {
        let request = SessionEntity.fetchRequest()
        request.predicate = NSPredicate(format: "workspaceID == %@", workspaceID)
        let existing = (try? context.fetch(request)) ?? []

        let incoming = Set(sessionIDs)
        for entity in existing where !incoming.contains(entity.id ?? "") {
            let sessionID = entity.id ?? ""

            let messageRequest = MessageEntity.fetchRequest()
            messageRequest.predicate = NSPredicate(format: "sessionID == %@", sessionID)
            ((try? context.fetch(messageRequest)) ?? []).forEach(context.delete)

            let partRequest = MessagePartEntity.fetchRequest()
            partRequest.predicate = NSPredicate(format: "sessionID == %@", sessionID)
            ((try? context.fetch(partRequest)) ?? []).forEach(context.delete)

            let todoRequest = TodoEntity.fetchRequest()
            todoRequest.predicate = NSPredicate(format: "sessionID == %@", sessionID)
            ((try? context.fetch(todoRequest)) ?? []).forEach(context.delete)

            let permissionRequest = PermissionEntity.fetchRequest()
            permissionRequest.predicate = NSPredicate(format: "workspaceID == %@ AND sessionID == %@", workspaceID, sessionID)
            ((try? context.fetch(permissionRequest)) ?? []).forEach(context.delete)

            let questionRequest = QuestionEntity.fetchRequest()
            questionRequest.predicate = NSPredicate(format: "workspaceID == %@ AND sessionID == %@", workspaceID, sessionID)
            ((try? context.fetch(questionRequest)) ?? []).forEach(context.delete)

            context.delete(entity)
        }
    }

    private static func replaceMessages(_ messages: [MessageEnvelope], sessionID: String, context: NSManagedObjectContext) {
        let messageRequest = MessageEntity.fetchRequest()
        messageRequest.predicate = NSPredicate(format: "sessionID == %@", sessionID)
        let existingMessages = (try? context.fetch(messageRequest)) ?? []
        existingMessages.forEach(context.delete)

        let partRequest = MessagePartEntity.fetchRequest()
        partRequest.predicate = NSPredicate(format: "sessionID == %@", sessionID)
        let existingParts = (try? context.fetch(partRequest)) ?? []
        existingParts.forEach(context.delete)

        for message in messages {
            let messageEntity: MessageEntity = insertEntity(in: context)
            messageEntity.id = message.info.id
            messageEntity.sessionID = message.info.sessionID
            messageEntity.payloadJSON = PersistenceCoders.encode(message)
            messageEntity.roleRaw = message.info.role.rawString
            messageEntity.createdAtMS = NSNumber(value: message.info.time.created)
            messageEntity.completedAtMS = message.info.time.completed.map(NSNumber.init(value:))
            messageEntity.parentID = message.info.parentID
            messageEntity.agent = message.info.agent
            messageEntity.modelProviderID = message.info.providerID ?? message.info.model?.providerID
            messageEntity.modelID = message.info.modelID ?? message.info.model?.modelID
            messageEntity.mode = message.info.mode
            messageEntity.pathCwd = message.info.path?.cwd
            messageEntity.pathRoot = message.info.path?.root
            messageEntity.cost = message.info.cost.map(NSNumber.init(value:))
            messageEntity.tokenTotal = message.info.tokens?.total.map(NSNumber.init(value:))
            messageEntity.tokenInput = message.info.tokens?.input.map(NSNumber.init(value:))
            messageEntity.tokenOutput = message.info.tokens?.output.map(NSNumber.init(value:))
            messageEntity.tokenReasoning = message.info.tokens?.reasoning.map(NSNumber.init(value:))
            messageEntity.tokenCacheRead = message.info.tokens?.cache?.read.map(NSNumber.init(value:))
            messageEntity.tokenCacheWrite = message.info.tokens?.cache?.write.map(NSNumber.init(value:))
            messageEntity.finish = message.info.finish
            messageEntity.summaryJSON = PersistenceCoders.encode(message.info.summary)
            messageEntity.errorJSON = PersistenceCoders.encode(message.info.error)

            for part in message.parts {
                let partEntity: MessagePartEntity = insertEntity(in: context)
                partEntity.id = part.id
                partEntity.sessionID = sessionID
                partEntity.messageID = message.info.id
                partEntity.payloadJSON = PersistenceCoders.encode(part)
                partEntity.typeRaw = part.type.rawString
                partEntity.text = part.text
                partEntity.synthetic = part.synthetic.map(NSNumber.init(value:))
                partEntity.ignored = part.ignored.map(NSNumber.init(value:))
                partEntity.startAtMS = part.time?.start.map(NSNumber.init(value:))
                partEntity.endAtMS = part.time?.end.map(NSNumber.init(value:))
                partEntity.compactedAtMS = part.time?.compacted.map(NSNumber.init(value:))
                partEntity.metadataJSON = PersistenceCoders.encode(part.metadata)
                partEntity.callID = part.callID
                partEntity.tool = part.tool
                partEntity.stateStatus = part.state?.status.rawString
                partEntity.stateInputJSON = PersistenceCoders.encode(part.state?.input)
                partEntity.stateRaw = part.state?.raw
                partEntity.stateOutput = part.state?.output
                partEntity.stateTitle = part.state?.title
                partEntity.stateMetadataJSON = PersistenceCoders.encode(part.state?.metadata)
                partEntity.stateError = part.state?.error
                partEntity.stateAttachmentsJSON = PersistenceCoders.encode(part.state?.attachments)
                partEntity.mime = part.mime
                partEntity.filename = part.filename
                partEntity.url = part.url
                partEntity.reason = part.reason
                partEntity.cost = part.cost.map(NSNumber.init(value:))
                partEntity.tokenTotal = part.tokens?.total.map(NSNumber.init(value:))
                partEntity.tokenInput = part.tokens?.input.map(NSNumber.init(value:))
                partEntity.tokenOutput = part.tokens?.output.map(NSNumber.init(value:))
                partEntity.tokenReasoning = part.tokens?.reasoning.map(NSNumber.init(value:))
                partEntity.tokenCacheRead = part.tokens?.cache?.read.map(NSNumber.init(value:))
                partEntity.tokenCacheWrite = part.tokens?.cache?.write.map(NSNumber.init(value:))
                partEntity.prompt = part.prompt
                partEntity.partDescription = part.description
                partEntity.agent = part.agent
                partEntity.modelProviderID = part.model?.providerID
                partEntity.modelID = part.model?.modelID
                partEntity.command = part.command
                partEntity.name = part.name
                partEntity.sourceValue = part.source?.value
                partEntity.sourceStart = part.source.map { NSNumber(value: $0.start) }
                partEntity.sourceEnd = part.source.map { NSNumber(value: $0.end) }
                partEntity.hashString = part.hash
                partEntity.filesJSON = PersistenceCoders.encode(part.files)
                partEntity.snapshot = part.snapshot
            }
        }
    }

    private static func upsertMessagePart(_ part: MessagePart, sessionID: String, context: NSManagedObjectContext) {
        if let messageID = part.messageID {
            ensureMessageEntityExists(messageID: messageID, sessionID: sessionID, createdAtMS: part.time?.start, context: context)
        }

        let request = MessagePartEntity.fetchRequest()
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "id == %@", part.id)
        let partEntity = (try? context.fetch(request).first) ?? insertEntity(in: context)
        partEntity.id = part.id
        partEntity.sessionID = sessionID
        partEntity.messageID = part.messageID
        partEntity.payloadJSON = PersistenceCoders.encode(part)
        partEntity.typeRaw = part.type.rawString
        partEntity.text = part.text
        partEntity.synthetic = part.synthetic.map(NSNumber.init(value:))
        partEntity.ignored = part.ignored.map(NSNumber.init(value:))
        partEntity.startAtMS = part.time?.start.map(NSNumber.init(value:))
        partEntity.endAtMS = part.time?.end.map(NSNumber.init(value:))
        partEntity.compactedAtMS = part.time?.compacted.map(NSNumber.init(value:))
        partEntity.metadataJSON = PersistenceCoders.encode(part.metadata)
        partEntity.callID = part.callID
        partEntity.tool = part.tool
        partEntity.stateStatus = part.state?.status.rawString
        partEntity.stateInputJSON = PersistenceCoders.encode(part.state?.input)
        partEntity.stateRaw = part.state?.raw
        partEntity.stateOutput = part.state?.output
        partEntity.stateTitle = part.state?.title
        partEntity.stateMetadataJSON = PersistenceCoders.encode(part.state?.metadata)
        partEntity.stateError = part.state?.error
        partEntity.stateAttachmentsJSON = PersistenceCoders.encode(part.state?.attachments)
        partEntity.mime = part.mime
        partEntity.filename = part.filename
        partEntity.url = part.url
        partEntity.reason = part.reason
        partEntity.cost = part.cost.map(NSNumber.init(value:))
        partEntity.tokenTotal = part.tokens?.total.map(NSNumber.init(value:))
        partEntity.tokenInput = part.tokens?.input.map(NSNumber.init(value:))
        partEntity.tokenOutput = part.tokens?.output.map(NSNumber.init(value:))
        partEntity.tokenReasoning = part.tokens?.reasoning.map(NSNumber.init(value:))
        partEntity.tokenCacheRead = part.tokens?.cache?.read.map(NSNumber.init(value:))
        partEntity.tokenCacheWrite = part.tokens?.cache?.write.map(NSNumber.init(value:))
        partEntity.prompt = part.prompt
        partEntity.partDescription = part.description
        partEntity.agent = part.agent
        partEntity.modelProviderID = part.model?.providerID
        partEntity.modelID = part.model?.modelID
        partEntity.command = part.command
        partEntity.name = part.name
        partEntity.sourceValue = part.source?.value
        partEntity.sourceStart = part.source.map { NSNumber(value: $0.start) }
        partEntity.sourceEnd = part.source.map { NSNumber(value: $0.end) }
        partEntity.hashString = part.hash
        partEntity.filesJSON = PersistenceCoders.encode(part.files)
        partEntity.snapshot = part.snapshot
    }

    private static func upsertMessageInfo(_ info: MessageInfo, sessionID: String, context: NSManagedObjectContext) {
        let request = MessageEntity.fetchRequest()
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "id == %@", info.id)
        let entity = (try? context.fetch(request).first) ?? insertEntity(in: context)
        apply(info: info, to: entity, sessionID: sessionID)
    }

    private static func ensureMessageEntityExists(messageID: String, sessionID: String, createdAtMS: Double?, context: NSManagedObjectContext) {
        let request = MessageEntity.fetchRequest()
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "id == %@", messageID)
        guard (try? context.fetch(request).first) == nil else { return }

        let info = MessageInfo(
            id: messageID,
            sessionID: sessionID,
            role: .assistant,
            time: .init(created: createdAtMS ?? Date().timeIntervalSince1970 * 1000, completed: nil),
            parentID: nil,
            agent: nil,
            model: nil,
            modelID: nil,
            providerID: nil,
            mode: nil,
            path: nil,
            cost: nil,
            tokens: nil,
            finish: nil,
            summary: nil,
            error: nil
        )
        let entity: MessageEntity = insertEntity(in: context)
        apply(info: info, to: entity, sessionID: sessionID)
    }

    private static func apply(info: MessageInfo, to entity: MessageEntity, sessionID: String) {
        entity.id = info.id
        entity.sessionID = sessionID
        entity.payloadJSON = PersistenceCoders.encode(MessageEnvelope(info: info, parts: []))
        entity.roleRaw = info.role.rawString
        entity.createdAtMS = NSNumber(value: info.time.created)
        entity.completedAtMS = info.time.completed.map(NSNumber.init(value:))
        entity.parentID = info.parentID
        entity.agent = info.agent
        entity.modelProviderID = info.providerID ?? info.model?.providerID
        entity.modelID = info.modelID ?? info.model?.modelID
        entity.mode = info.mode
        entity.pathCwd = info.path?.cwd
        entity.pathRoot = info.path?.root
        entity.cost = info.cost.map(NSNumber.init(value:))
        entity.tokenTotal = info.tokens?.total.map(NSNumber.init(value:))
        entity.tokenInput = info.tokens?.input.map(NSNumber.init(value:))
        entity.tokenOutput = info.tokens?.output.map(NSNumber.init(value:))
        entity.tokenReasoning = info.tokens?.reasoning.map(NSNumber.init(value:))
        entity.tokenCacheRead = info.tokens?.cache?.read.map(NSNumber.init(value:))
        entity.tokenCacheWrite = info.tokens?.cache?.write.map(NSNumber.init(value:))
        entity.finish = info.finish
        entity.summaryJSON = PersistenceCoders.encode(info.summary)
        entity.errorJSON = PersistenceCoders.encode(info.error)
    }

    private static func applyMessagePartDelta(partID: String, field: MessagePartDeltaField, delta: String, context: NSManagedObjectContext) {
        let request = MessagePartEntity.fetchRequest()
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "id == %@", partID)
        guard let entity = try? context.fetch(request).first else { return }

        if var part = PersistenceCoders.decode(MessagePart.self, from: entity.payloadJSON) {
            part.apply(delta: delta, to: field)
            upsertMessagePart(part, sessionID: entity.sessionID ?? part.sessionID ?? "", context: context)
            return
        }

        switch field {
        case .text:
            entity.text = (entity.text ?? "") + delta
        case .output:
            entity.stateOutput = (entity.stateOutput ?? "") + delta
        case .error:
            entity.stateError = (entity.stateError ?? "") + delta
        case .unknown:
            break
        }
    }

    private static func removeMessagePart(partID: String, context: NSManagedObjectContext) {
        let request = MessagePartEntity.fetchRequest()
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "id == %@", partID)
        if let entity = try? context.fetch(request).first {
            context.delete(entity)
        }
    }

    private static func removeMessage(messageID: String, context: NSManagedObjectContext) {
        let messageRequest = MessageEntity.fetchRequest()
        messageRequest.fetchLimit = 1
        messageRequest.predicate = NSPredicate(format: "id == %@", messageID)
        if let message = try? context.fetch(messageRequest).first {
            context.delete(message)
        }

        let partRequest = MessagePartEntity.fetchRequest()
        partRequest.predicate = NSPredicate(format: "messageID == %@", messageID)
        ((try? context.fetch(partRequest)) ?? []).forEach(context.delete)
    }

    private static func replaceTodos(_ todos: [SessionTodo], sessionID: String, context: NSManagedObjectContext) {
        let request = TodoEntity.fetchRequest()
        request.predicate = NSPredicate(format: "sessionID == %@", sessionID)
        let existing = (try? context.fetch(request)) ?? []
        existing.forEach(context.delete)

        for todo in todos {
            let entity: TodoEntity = insertEntity(in: context)
            entity.id = "\(sessionID)::\(todo.content)"
            entity.sessionID = sessionID
            entity.payloadJSON = PersistenceCoders.encode(todo)
            entity.content = todo.content
            entity.statusRaw = todo.status.rawString
            entity.priorityRaw = todo.priority.rawString
        }
    }

    private static func replaceQuestions(_ questions: [QuestionRequest], workspaceID: String, context: NSManagedObjectContext) {
        let request = QuestionEntity.fetchRequest()
        request.predicate = NSPredicate(format: "workspaceID == %@", workspaceID)
        let existing = (try? context.fetch(request)) ?? []
        existing.forEach(context.delete)

        for question in questions {
            let entity: QuestionEntity = insertEntity(in: context)
            entity.id = question.id
            entity.sessionID = question.sessionID
            entity.workspaceID = workspaceID
            entity.payloadJSON = PersistenceCoders.encode(question)
            entity.questionsJSON = PersistenceCoders.encode(question.questions)
        }
    }

    private static func replacePermissions(_ permissions: [PermissionRequest], workspaceID: String, context: NSManagedObjectContext) {
        let request = PermissionEntity.fetchRequest()
        request.predicate = NSPredicate(format: "workspaceID == %@", workspaceID)
        let existing = (try? context.fetch(request)) ?? []
        existing.forEach(context.delete)

        for permission in permissions {
            let entity: PermissionEntity = insertEntity(in: context)
            entity.id = permission.id
            entity.sessionID = permission.sessionID
            entity.workspaceID = workspaceID
            entity.payloadJSON = PersistenceCoders.encode(permission)
            entity.permission = permission.permission
            entity.patternsJSON = PersistenceCoders.encode(permission.patterns)
            entity.metadataJSON = PersistenceCoders.encode(permission.metadata)
            entity.alwaysJSON = PersistenceCoders.encode(permission.always)
            entity.toolMessageID = permission.tool?.messageID
            entity.toolCallID = permission.tool?.callID
        }
    }

    private static func replaceStatuses(_ statuses: [String: SessionStatus], workspaceID: String, context: NSManagedObjectContext) {
        let request = SessionEntity.fetchRequest()
        request.predicate = NSPredicate(format: "workspaceID == %@", workspaceID)
        let entities = (try? context.fetch(request)) ?? []
        for entity in entities {
            guard let id = entity.id else { continue }
            if let status = statuses[id] {
                setStatus(status, for: id, workspaceID: workspaceID, context: context)
            } else {
                entity.statusType = nil
                entity.statusLabel = nil
                entity.statusAttempt = nil
                entity.statusNextMS = nil
            }
        }
    }

    private static func setStatus(_ status: SessionStatus, for sessionID: String, workspaceID: String, context: NSManagedObjectContext) {
        let request = SessionEntity.fetchRequest()
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "id == %@ AND workspaceID == %@", sessionID, workspaceID)
        guard let entity = try? context.fetch(request).first else { return }

        switch status {
        case .idle:
            entity.statusType = "idle"
            entity.statusLabel = "Idle"
            entity.statusAttempt = nil
            entity.statusNextMS = nil
        case .busy:
            entity.statusType = "busy"
            entity.statusLabel = "Busy"
            entity.statusAttempt = nil
            entity.statusNextMS = nil
        case let .retry(attempt, message, next):
            entity.statusType = "retry"
            entity.statusLabel = message
            entity.statusAttempt = NSNumber(value: attempt)
            entity.statusNextMS = NSNumber(value: next)
        case let .unknown(raw):
            entity.statusType = raw
            entity.statusLabel = raw.capitalized
            entity.statusAttempt = nil
            entity.statusNextMS = nil
        }
    }

    private static func clearStatus(for sessionID: String, workspaceID: String, context: NSManagedObjectContext) {
        let request = SessionEntity.fetchRequest()
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "id == %@ AND workspaceID == %@", sessionID, workspaceID)
        guard let entity = try? context.fetch(request).first else { return }

        entity.statusType = nil
        entity.statusLabel = nil
        entity.statusAttempt = nil
        entity.statusNextMS = nil
    }

    private static func recomputeSessionDerivedState(
        workspaceID: String,
        modelContextLimits: [ModelContextKey: Int],
        context: NSManagedObjectContext,
        sessionIDs: [String]? = nil
    ) {
        let request = SessionEntity.fetchRequest()
        if let sessionIDs, !sessionIDs.isEmpty {
            request.predicate = NSPredicate(format: "workspaceID == %@ AND id IN %@", workspaceID, sessionIDs)
        } else {
            request.predicate = NSPredicate(format: "workspaceID == %@", workspaceID)
        }

        let sessions = (try? context.fetch(request)) ?? []
        for session in sessions {
            guard let sessionID = session.id else { continue }

            let todoRequest = TodoEntity.fetchRequest()
            todoRequest.predicate = NSPredicate(format: "sessionID == %@", sessionID)
            let todos = ((try? context.fetch(todoRequest)) ?? []).compactMap { PersistenceCoders.decode(SessionTodo.self, from: $0.payloadJSON) }
            let relevant = todos.filter { $0.status != .cancelled }
            session.todoCompletedCount = NSNumber(value: relevant.filter { $0.status == .completed }.count)
            session.todoTotalCount = NSNumber(value: relevant.count)
            session.todoActionableCount = NSNumber(value: relevant.filter { $0.status == .pending || $0.status == .inProgress }.count)

            let permissionRequest = PermissionEntity.fetchRequest()
            permissionRequest.predicate = NSPredicate(format: "workspaceID == %@ AND sessionID == %@", workspaceID, sessionID)
            let permissions = (try? context.fetch(permissionRequest)) ?? []
            session.hasPendingPermission = NSNumber(value: !permissions.isEmpty)

            let messageRequest = MessageEntity.fetchRequest()
            messageRequest.predicate = NSPredicate(format: "sessionID == %@", sessionID)
            messageRequest.sortDescriptors = [NSSortDescriptor(key: "createdAtMS", ascending: false)]
            let messages = (try? context.fetch(messageRequest)) ?? []
            session.lastMessageCreatedAtMS = messages.first?.createdAtMS

            if let payload = messages.compactMap({ PersistenceCoders.decode(MessageEnvelope.self, from: $0.payloadJSON) }).first(where: {
                $0.totalTokens != nil && $0.info.modelContextKey != nil
            }),
               let modelKey = payload.info.modelContextKey,
               let usedTokens = payload.totalTokens,
               let limit = modelContextLimits[modelKey],
               limit > 0 {
                let percentage = min(100, Int((Double(usedTokens) / Double(limit) * 100).rounded()))
                session.lastContextUsagePercent = NSNumber(value: percentage)
            } else {
                session.lastContextUsagePercent = nil
            }

            let updated = max(session.updatedAtMS?.doubleValue ?? 0, session.lastMessageCreatedAtMS?.doubleValue ?? 0)
            session.sortUpdatedAtMS = NSNumber(value: updated)
        }
    }

    private static func fetchByID<T: NSManagedObject>(_ type: T.Type, ids: [String], context: NSManagedObjectContext) -> [String: T] {
        guard !ids.isEmpty else { return [:] }
        let request = NSFetchRequest<T>(entityName: String(describing: type))
        request.predicate = NSPredicate(format: "id IN %@", ids)
        let objects = (try? context.fetch(request)) ?? []
        return objects.reduce(into: [String: T]()) { result, object in
            if let id = object.value(forKey: "id") as? String {
                result[id] = object
            }
        }
    }

    private static func insertEntity<T: NSManagedObject>(in context: NSManagedObjectContext) -> T {
        guard
            let entityName = String(describing: T.self).split(separator: ".").last.map(String.init),
            let entity = NSEntityDescription.entity(forEntityName: entityName, in: context)
        else {
            fatalError("Missing entity description for \(T.self)")
        }

        return T(entity: entity, insertInto: context)
    }
}

private extension Duration {
    var milliseconds: Int64 {
        let components = components
        return components.seconds * 1_000 + Int64(components.attoseconds / 1_000_000_000_000_000)
    }
}

extension WorkspaceEntity {
    @nonobjc class func fetchRequest() -> NSFetchRequest<WorkspaceEntity> {
        NSFetchRequest<WorkspaceEntity>(entityName: "WorkspaceEntity")
    }
}

extension SessionEntity {
    @nonobjc class func fetchRequest() -> NSFetchRequest<SessionEntity> {
        NSFetchRequest<SessionEntity>(entityName: "SessionEntity")
    }
}

extension MessageEntity {
    @nonobjc class func fetchRequest() -> NSFetchRequest<MessageEntity> {
        NSFetchRequest<MessageEntity>(entityName: "MessageEntity")
    }
}

extension MessagePartEntity {
    @nonobjc class func fetchRequest() -> NSFetchRequest<MessagePartEntity> {
        NSFetchRequest<MessagePartEntity>(entityName: "MessagePartEntity")
    }
}

extension PermissionEntity {
    @nonobjc class func fetchRequest() -> NSFetchRequest<PermissionEntity> {
        NSFetchRequest<PermissionEntity>(entityName: "PermissionEntity")
    }
}

extension QuestionEntity {
    @nonobjc class func fetchRequest() -> NSFetchRequest<QuestionEntity> {
        NSFetchRequest<QuestionEntity>(entityName: "QuestionEntity")
    }
}

extension TodoEntity {
    @nonobjc class func fetchRequest() -> NSFetchRequest<TodoEntity> {
        NSFetchRequest<TodoEntity>(entityName: "TodoEntity")
    }
}

extension SessionPaneEntity {
    @nonobjc class func fetchRequest() -> NSFetchRequest<SessionPaneEntity> {
        NSFetchRequest<SessionPaneEntity>(entityName: "SessionPaneEntity")
    }
}
