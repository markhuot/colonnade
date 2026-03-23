# Session-Scoped SSE Sync Plan

## Goal

- Make SSE the driver of UI invalidation.
- Apply each event to the smallest possible slice of state.
- Stop rebuilding full workspace snapshots during normal streaming.
- Treat Core Data as persistence and query support, not as the trigger for whole-app refreshes.

## Current Problems

- `OpenCodeAppModel` publishes one large `PersistenceSnapshot` value.
- SSE events in `OpenCodeFeature/WorkspaceSyncCoordinator.swift` often fan out into broad refreshes:
  - `message.updated` -> session message refresh + session refresh + status refresh
  - `message.part.*` -> full session message refresh
  - interaction events -> full interaction refresh
- `OpenCodeAppModel` currently observes Core Data merges and reloads the whole snapshot after writes.
- `PersistenceRepository.loadSnapshot(...)` fetches all visible sessions, all messages for those sessions, all parts, all questions, all permissions, and pane state.
- Instrumentation shows that full snapshot reloads cost roughly `1.3s`-`1.6s` normally, with worse spikes, while publication cost is small.

## Target Architecture

### Store Shape

Replace the monolithic `snapshot`-driven UI path with a session-scoped store.

Suggested shape:

- `WorkspaceStore`
  - `workspaceMeta` for selected directory and lightweight workspace-level flags
  - `sessionOrder: [String]`
  - `sessionsByID: [String: SessionRecord]`
  - `interactionsBySession: [String: SessionInteractions]`
  - `paneStateBySession: [String: SessionPaneState]`
- `SessionRecord`
  - sidebar/header projection fields only
  - message list for that session only
  - todo list for that session only
  - status, permission state, question state for that session only

The key property is isolation: if session `A` changes, only `SessionRecord[A]` mutates.

### Data Flow

Normal streaming path:

1. SSE event arrives.
2. `WorkspaceSyncCoordinator` classifies the event.
3. Coordinator performs one of:
   - direct in-memory mutation from event payload
   - session-scoped refetch for the affected resource
   - rare workspace-scoped refetch when the event truly changes workspace shape
4. Store publishes only the changed session/global slice.
5. Persistence mirrors the change in the background.

Important inversion:

- UI updates should come from the SSE/event pipeline.
- Persistence writes should follow that pipeline.
- Core Data merge notifications should not drive whole-workspace UI reloads.

## Event Mapping

### Apply Directly From Payload

These events already contain enough information, or nearly enough information, to mutate a single slice directly.

- `session.created`
  - payload includes full `OpenCodeSession` in `info`
  - update only that session record and session ordering
- `session.updated`
  - payload includes full `OpenCodeSession` in `info`
  - update only that session record
- `session.deleted`
  - payload includes full `OpenCodeSession` in `info`
  - remove only that session and its associated in-memory slices
- `session.status`
  - payload includes `sessionID` and `status`
  - update only that session's status/indicator
- `message.part.updated`
  - payload appears to include `part`
  - update one part in one message in one session
- `message.part.delta`
  - payload includes `delta`, `field`, and part/session identity
  - append delta to one part field in one message in one session
- `message.part.removed`
  - payload includes enough identity to remove a single part
  - remove one part from one message in one session

### Session-Scoped Refetch

These events should not trigger workspace-wide refreshes, but payloads are currently too incomplete to apply perfectly without a targeted fetch.

- `message.updated`
  - current payload handling only decodes `MessageInfo`
  - first pass: refetch messages for `info.sessionID` only
  - future improvement: if the event payload can include the full message envelope, mutate directly
- `message.removed`
  - current code only relies on `sessionID`
  - first pass: refetch messages for that session only
  - future improvement: remove by `messageID` directly if payload is sufficient
- `todo.updated`
  - first pass: refetch todos for the specified session only
  - never refetch all open sessions unless the server omits `sessionID`

### Interaction-Scoped Refetch

These are still session-scoped, but they belong in a separate interaction channel.

- `permission.asked`
- `permission.replied`
- `question.asked`
- `question.replied`
- `question.rejected`

Current first pass:

- refetch interactions for the affected session only if the payload exposes `sessionID`
- otherwise fall back to interaction-wide refresh, but keep it out of message/session paths

Future ideal state:

- decode these payloads into direct `PermissionRequest` / `QuestionRequest` mutations

### Rare Workspace-Scoped Refreshes

These are the only events that should justify broader recomputation.

- initial `start(...)`
- explicit manual refresh
- reconnect after a long disconnect where event continuity is uncertain
- any future server event that explicitly means "workspace resync required"

Routine streaming should not call `applyWorkspaceSnapshot(...)`.

## What To Remove From The Current Path

From normal SSE handling, remove these broad side effects:

- `message.updated` -> `scheduleSessionRefresh()`
- `message.updated` -> global `scheduleStatusRefresh()` unless status actually changed
- `message.part.*` -> full message list refetch when direct mutation is possible
- Core Data `NSManagedObjectContextObjectsDidChange` -> `reloadSnapshot(...)`

Those paths are the source of current cross-pane invalidation.

## Required Store/API Changes

### App State

`OpenCodeAppModel` should stop being a wrapper around `PersistenceSnapshot` for live session rendering.

Instead it should own or consume a session-scoped store with operations like:

- `applySession(_ session: OpenCodeSession)`
- `removeSession(id: String)`
- `applyStatus(sessionID: String, status: SessionStatus)`
- `replaceMessages(sessionID: String, messages: [MessageEnvelope])`
- `upsertMessage(sessionID: String, message: MessageEnvelope)`
- `removeMessage(sessionID: String, messageID: String)`
- `upsertMessagePart(sessionID: String, messageID: String, part: MessagePart)`
- `applyMessagePartDelta(sessionID: String, messageID: String, partID: String, field: MessagePartDeltaField, delta: String)`
- `removeMessagePart(sessionID: String, messageID: String, partID: String)`
- `replaceTodos(sessionID: String, todos: [SessionTodo])`
- `replaceInteractions(sessionID: String, questions: [QuestionRequest], permissions: [PermissionRequest])`

### Persistence Repository

`PersistenceRepository` should support narrow writes and narrow reads.

Needed APIs:

- session-scoped read helpers
  - `loadSession(sessionID:)`
  - `loadMessages(sessionID:)`
  - `loadTodos(sessionID:)`
  - `loadInteractions(sessionID:)`
- event-scoped write helpers
  - `upsertMessagePart(...)`
  - `applyMessagePartDelta(...)`
  - `removeMessagePart(...)`
  - `removeMessage(...)`
  - `upsertSession(...)`
  - `removeSession(...)`

Persistence should keep derived fields current for the affected session only.

### Sync Coordinator

`WorkspaceSyncCoordinator` should become an event router, not a workspace refresher.

It should:

- classify events by scope: `session`, `message`, `part`, `todo`, `interaction`, `workspace`
- call one targeted mutation per event
- use session-scoped refetch only when payload fidelity is insufficient
- stop scheduling unrelated refreshes

## Recommended Migration Order

### Phase 1: Remove Core Data Merge-Driven UI Reloads

- Introduce the session-scoped in-memory store.
- Keep Core Data writes, but stop using merge notifications to rebuild `snapshot`.
- Make UI render from the new store for sessions/messages/todos/interactions.

### Phase 2: Convert Event Handling To Narrow Mutations

- `session.created/updated/deleted`
- `session.status`
- `message.updated` -> session-only refetch
- `message.removed` -> session-only refetch
- `todo.updated` -> session-only refetch

This phase alone should remove most broad invalidation.

### Phase 3: Eliminate Message Refetches For Part Events

- Apply `message.part.updated`
- Apply `message.part.delta`
- Apply `message.part.removed`

At that point token streaming becomes true incremental rendering.

### Phase 4: Tighten Interaction Updates

- make permission/question updates session-scoped
- decode payloads directly if possible

### Phase 5: Relegate Core Data To Persistence/Bootstrap

- use Core Data for app launch hydration, background persistence, and verification
- do not use it as the hot path for stream-time UI updates

## Correctness Rules

- One event should mutate one scope.
- If an event references `sessionID = X`, only session `X` should update unless the event explicitly represents workspace-level structure.
- A session-scoped refetch may update only:
  - that session's messages
  - that session's todos
  - that session's interactions
  - that session's status
- No routine message event should trigger full session list reloads.
- No routine message event should trigger workspace-wide snapshot rebuilds.

## Open Questions

- Does the server's `message.updated` payload contain enough fields to synthesize a full `MessageEnvelope` without refetch?
- Does `message.removed` include `messageID` consistently?
- Do interaction events expose enough session-scoped payload to avoid interaction refetches?
- Should the session list ordering be recomputed only when a session's `sortUpdatedAt` changes, rather than on every event?

## Initial Implementation Target

The first "right" implementation should achieve this:

- pane 2 streaming updates mutate only pane 2 session state
- pane 1 typing remains smooth because its state is untouched
- Core Data still records the same state in the background
- full workspace reload happens only on bootstrap, manual refresh, or explicit resync
