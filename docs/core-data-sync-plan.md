# Core Data Sync Plan

## Goals

- Move session, message, status, todo, and interaction state into a single Core Data SQLite store.
- Keep network sync and event processing off the main actor as much as possible.
- Let SwiftUI react to persisted state changes instead of manually coordinating repeated re-queries.
- Replace the bespoke pane SQLite store with Core Data-backed workspace state.
- Treat this as a fresh-store rollout; no migration compatibility is required.

## Current Problems

- `OpenCodeAppModel` and `SessionStore` are both main-actor owned, so event fan-out, sorting, and large in-memory merges happen on the UI thread.
- SSE events trigger overlapping refreshes for sessions, statuses, messages, and todos.
- Streaming message deltas still schedule full message reloads.
- Activity polling re-fetches many resources every second.
- Secondary session windows build their own app state and duplicate sync work.
- Sidebar and headers derive status/title/context data from transient arrays instead of persisted projections.

## Target Architecture

### Persistent Store

Use one `NSPersistentContainer` with a SQLite backing store under Application Support.

Entities:

- `WorkspaceEntity`
  - `id`, `directory`, `projectName`, `isSelected`, `lastSyncedAt`
- `WorkspaceUIStateEntity`
  - `workspaceID`, `selectedDirectory`, `focusedSessionID`
- `SessionEntity`
  - server session fields
  - denormalized display fields for sidebar/header: `statusType`, `statusLabel`, `hasPendingPermission`, `todoCompletedCount`, `todoTotalCount`, `todoActionableCount`, `lastContextUsagePercent`, `lastMessageCreatedAt`, `sortUpdatedAt`
- `MessageEntity`
  - message metadata keyed by server message id
- `MessagePartEntity`
  - part payload keyed by server part id
- `QuestionEntity`
- `PermissionEntity`
- `TodoEntity`
- `SessionPaneEntity`
  - persisted pane position, width, hidden state per workspace/session

Relationships should be normalized enough for fetches, but session-level projection fields should avoid recomputing sidebar state from message trees on every render.

### Sync Layer

Create a single shared sync coordinator per workspace.

Responsibilities:

- own SSE connection
- own fallback polling
- coalesce refresh requests by resource type and session id
- write decoded payloads into a background managed object context
- batch streaming deltas before persisting them
- update denormalized session projection fields during writes

Likely types:

- `PersistenceController`
- `WorkspaceRepository`
- `WorkspaceSyncCoordinator`
- `WorkspaceSyncRegistry` for sharing one coordinator across windows

### UI Layer

- `OpenCodeAppModel` becomes a thin view-model/controller for selection, drafts, commands, and window concerns.
- Views read sessions/messages/todos from Core Data fetch requests instead of `SessionStore` dictionaries.
- Multi-window support shares the same persistent container and sync coordinator.
- Manual `objectWillChange.send()` calls should largely disappear.

## Implementation Steps

1. Add a Core Data model and persistence controller.
2. Port pane persistence and last-selected-directory state into Core Data.
3. Introduce managed object wrappers / fetch helpers for sessions, messages, todos, and interactions.
4. Build a background sync coordinator that mirrors the current `WorkspaceService` behavior, but persists results instead of mutating in-memory store state.
5. Refactor app state to drive sync start/stop and UI-only state.
6. Refactor sidebar and session views to use fetched Core Data records.
7. Remove `SessionStore` and the custom SQLite pane store.
8. Regenerate the Xcode project and verify the app builds cleanly.

## Immediate Refactor Strategy

To keep the change manageable, the first implementation pass should:

- preserve the current network API client and event decoding
- preserve current SwiftUI structure where possible
- replace in-memory persistence first, then trim legacy code paths
- keep draft text in memory for now
- keep model catalog/context limit loading outside Core Data for now unless it proves necessary

## Risks To Watch

- Writing every stream delta immediately can still create churn; debounce high-frequency part updates.
- SwiftUI fetches for deep message graphs can still be expensive if sort/filter definitions are loose.
- Cross-window sync ownership must be centralized, or performance will regress again.
- Large JSON blobs in Core Data should be minimized; store only the fields needed for rendering and command flow.

## Done Criteria

- One workspace has one sync pipeline, regardless of number of windows.
- Sidebar and session views render from Core Data-backed fetches.
- Status icon, title, todo progress, and updated timestamps are driven from persisted session state.
- Pane persistence no longer uses raw SQLite.
- The app builds and runs from a fresh install without migration support.
