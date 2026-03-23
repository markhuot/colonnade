# Guardian Sessions

## Summary

- Implement guardians entirely in the Mac app, without any OpenCode API changes.
- A guardian is local client-side behavior attached to a parent session.
- It observes the parent session's visible state and can influence the session in two ways:
  - answer `question.asked` requests
  - react when the agent appears to stop and decide whether to send a follow-up prompt
- The only interaction type a guardian must never handle is permissions.
- Guardian support is opt-in per session and must degrade cleanly to normal user-driven behavior.

## Constraint

This app sits on top of the existing OpenCode API, and that API is fixed.

That means:

- we cannot add guardian-specific endpoints
- we cannot change server-side session payloads
- we cannot ask the server runtime to execute a separate guardian session
- we cannot make the server aware of guardian state beyond what the client can already express through existing calls

So the implementation has to be entirely client-side, using the existing Swift app's local persistence, live store, and current send/reply APIs.

## What Is Still Possible

The current app already has enough hooks for a meaningful client-only guardian:

- the app receives `question.asked` and related interaction updates through `WorkspaceSyncCoordinator` in `OpenCodeFeature/WorkspaceSyncCoordinator.swift:436`
- the app can already answer questions through `replyToQuestion(...)` in `OpenCodeKit/OpenCodeAPIClient.swift:155`
- the app can already send follow-up prompts through `sendMessage(...)` in `OpenCodeKit/OpenCodeAPIClient.swift:98`
- the live store already exposes messages, todos, questions, and permissions per session in `OpenCodeFeature/WorkspaceLiveStore.swift:16`
- stop-like completion signals already exist in visible message state through `MessageEnvelope.stepFinish` in `OpenCodeKit/SharedModels.swift:697` and are surfaced in the timeline UI in `OpenCodeMac/Views/SessionColumnView.swift:702`

That gives us a clear client-only path:

- store local guardian config keyed by parent session id
- watch for pending `QuestionRequest`s in the parent session
- watch for stop/completion transitions in the parent session timeline
- synthesize a local guardian decision from visible context and guardian instructions
- either answer the question via the existing question reply API or send an additional prompt via the existing message send API

## What Is Not Possible Client-Side

Without API support, a guardian cannot be a true server-side subagent.

Specifically, it cannot:

- observe hidden chain-of-thought or server-only runtime state
- access the parent session's real system prompt unless that prompt is explicitly stored locally by the app
- participate inside the server execution loop before the server decides to ask a question or stop
- inject hidden control messages into OpenCode through a dedicated guardian protocol
- act as a real child session recognized by OpenCode itself

So the right mental model is not "server subagent".

The right mental model is:

- a local session guardian policy running in the Mac app
- it watches the same visible state the user sees
- it can answer questions and continue a run by sending another prompt
- it never handles permissions

## Behavioral Contract

Guardian support should cover all client-side intervention opportunities except permissions.

### Allowed Guardian Actions

- answer a pending `QuestionRequest`
- decide to do nothing and let the user continue
- send a follow-up prompt to the session after the agent appears to stop

### Forbidden Guardian Actions

- answering `PermissionRequest`
- auto-approving, rejecting, or annotating permissions
- direct tool execution on behalf of the session
- editing synced server state outside existing user-facing APIs

## Trigger Types

The guardian should respond to two classes of triggers.

### 1. Question Trigger

When a new `QuestionRequest` appears for a guardian-enabled session:

- the guardian evaluates whether it can answer
- if yes, it submits `replyToQuestion(...)`
- if no, it defers to the user

### 2. Stop Trigger

When the agent appears to have stopped, the guardian evaluates whether the run should continue.

For this app, a stop should initially be inferred from visible message state rather than new server events.

Initial stop heuristics:

- a new assistant message gains a `stepFinish`
- the finish reason is not an obvious intermediate tool-call continuation
- the session is no longer actively accumulating parts for that turn

The current UI already treats `stepFinish` specially, and excludes the `tool-calls` reason when rendering a finish marker in `OpenCodeMac/Views/SessionColumnView.swift:702`. That is a good initial signal for guardian stop evaluation.

## Recommended V1 Scope

V1 should support:

- question answering
- stop evaluation followed by optional follow-up prompting

V1 should not support:

- permission handling of any kind
- tool interception
- server-side guardian child sessions
- workspace-wide orchestration across multiple sessions

## User Experience

### Session-Level Opt-In

Each session can have a local guardian configuration.

Suggested fields:

```json
{
  "sessionID": "sess_123",
  "isEnabled": true,
  "instructions": "Watch for unanswered implementation gaps, missing acceptance criteria, and incomplete task completion. Never answer permissions.",
  "useRecentMessagesCount": 12,
  "includeTodos": true,
  "allowQuestionAnswers": true,
  "allowFollowUpPrompts": true,
  "maxFollowUpsPerTurn": 1,
  "debugLogging": false
}
```

Notes:

- `isEnabled` is the opt-in switch.
- `instructions` is the guardian-specific policy authored by the user.
- `allowQuestionAnswers` and `allowFollowUpPrompts` allow narrow enablement if needed.
- `maxFollowUpsPerTurn` prevents local loops.
- `debugLogging` helps inspect behavior during rollout.

### UI Affordances

Suggested UI for the session screen:

- `Guardian` toggle
- guardian instructions text area
- toggles for `Answer Questions` and `Continue After Stop`
- small note stating `Guardians never answer permissions`
- optional badge such as `Guardian On`

Nice-to-have:

- show when a guardian answered a question
- show when a guardian continued the run with a follow-up prompt
- show the last guardian decision in a debug sheet or inspector

## Architecture

## Core Idea

Add a local `GuardianCoordinator` in the Mac app.

Responsibilities:

- load and persist guardian config per session
- observe session-scoped question state from `WorkspaceLiveStore`
- observe stop/completion transitions from visible message state
- decide whether a question or stop is eligible for guardian handling
- build local guardian context
- call a local decision engine
- submit answers through `replyToQuestion(...)`
- submit follow-up prompts through `sendMessage(...)`
- record local audit/debug information

This should sit alongside `WorkspaceSyncCoordinator`, not inside the OpenCode API client.

## Proposed Types

### `GuardianConfiguration`

```swift
struct GuardianConfiguration: Codable, Hashable, Sendable {
    let sessionID: String
    var isEnabled: Bool
    var instructions: String
    var useRecentMessagesCount: Int
    var includeTodos: Bool
    var allowQuestionAnswers: Bool
    var allowFollowUpPrompts: Bool
    var maxFollowUpsPerTurn: Int
    var debugLogging: Bool
}
```

### `GuardianTrigger`

```swift
enum GuardianTrigger: Sendable {
    case question(QuestionRequest)
    case stop(GuardianStopEvent)
}
```

### `GuardianStopEvent`

```swift
struct GuardianStopEvent: Hashable, Sendable {
    let sessionID: String
    let messageID: String
    let finishPartID: String
    let reason: String?
}
```

### `GuardianAction`

```swift
enum GuardianAction: Sendable {
    case answerQuestion(requestID: String, answers: [[String]])
    case sendFollowUpPrompt(String)
    case deferToUser(reason: String)
    case ignore(reason: String)
}
```

### `GuardianContext`

Suggested contents:

- `sessionID`
- trigger type
- recent `MessageEnvelope`s
- current `[SessionTodo]`
- current `[QuestionRequest]`
- guardian instructions
- visible finish metadata when evaluating a stop

## Decision Engine

There are two viable Swift-side approaches.

### Option A: Deterministic Rule Engine

Use heuristics and structured policies.

Examples:

- answer straightforward multiple-choice questions using explicit guardian instructions
- on stop, check whether todos remain actionable and whether the final assistant turn appears to have concluded without addressing them
- on stop, continue only when the guardian can form a narrow, actionable follow-up prompt

Pros:

- no model cost
- deterministic
- easy to test

Cons:

- weaker for nuanced continuation decisions

### Option B: Local Model-Backed Guardian

Use a separate local model call from the Mac app to choose actions based on visible context.

Suggested protocol:

```swift
protocol GuardianDeciding: Sendable {
    func decide(context: GuardianContext) async throws -> GuardianAction
}
```

If this route is taken later, tests must use fakes and never hit real providers.

### Recommendation

Design around `GuardianDeciding`, but ship V1 with a deterministic implementation.

That keeps the architecture open while staying consistent with the repo's no-real-inference-in-tests guidance.

## Triggering Flow

### Question Flow

1. `WorkspaceSyncCoordinator` refreshes interactions for a session.
2. `WorkspaceLiveStore` updates questions and permissions.
3. `GuardianCoordinator` is notified for that session.
4. Guardian inspects pending questions.
5. For each new question:
   - if permissions are also pending, ignore permissions entirely
   - if guardian config allows question handling, evaluate the question
   - submit `replyToQuestion(...)` for `.answerQuestion`
   - otherwise leave it for the user

### Stop Flow

1. `WorkspaceSyncCoordinator` applies message part updates.
2. When a new `stepFinish` arrives for a session, the app constructs a `GuardianStopEvent`.
3. `GuardianCoordinator` evaluates the stop event with recent visible session context.
4. If the guardian believes continuation is necessary, it sends a follow-up prompt via `sendMessage(...)`.
5. Otherwise it records a no-op/defer decision.

## Stop Detection Details

Because the server does not give us a dedicated guardian hook, stop detection must be derived from the timeline.

Recommended initial rule:

- treat a newly applied `MessagePart` of type `.stepFinish` as a stop candidate

Additional filters:

- ignore stop candidates where `reason == "tool-calls"`
- ignore duplicate finish parts for the same message
- ignore stop candidates if a guardian follow-up for that same message has already been sent

Possible future refinement:

- debounce briefly to ensure no more parts are still arriving
- correlate with session status becoming idle if that proves more reliable

## Loop Prevention

This is the main additional risk once guardians can send prompts.

Required protections:

- track processed question ids so the same question is not answered twice
- track processed stop events by `finishPartID`
- track guardian-originated follow-up prompts per parent turn
- enforce `maxFollowUpsPerTurn`
- if the last visible user message was guardian-originated and the next stop arrives without material progress, do not continue automatically again

Concretely, the guardian needs local memory like:

- `answeredQuestionIDs`
- `handledStopEventIDs`
- `followUpCountByMessageID`
- `lastGuardianPromptBySession`

## Context Construction

Because this is client-only, context quality matters.

Recommended inputs:

- guardian instructions
- pending `QuestionRequest`s
- the last N messages from `SessionLiveState.messages`
- current todos from `SessionLiveState.todos`
- the latest assistant message and its `stepFinish`
- visible tool outputs if present in the recent window

Recommended omissions for V1:

- full workspace-wide scan
- hidden or inferred system prompt state we do not actually possess
- permission contents as actionable items for the guardian

## Persistence

Guardian config is local app state, not server state.

That means it belongs in Core Data.

### Recommended Persistence Shape

Add a new entity, for example `GuardianConfigEntity`:

- `sessionID` (unique, indexed)
- `workspaceID`
- `isEnabled`
- `instructions`
- `useRecentMessagesCount`
- `includeTodos`
- `allowQuestionAnswers`
- `allowFollowUpPrompts`
- `maxFollowUpsPerTurn`
- `debugLogging`
- `updatedAt`

Optional local audit entity:

- `GuardianDecisionLogEntity`
  - `id`
  - `sessionID`
  - `triggerType`
  - `triggerID`
  - `actionType`
  - `summary`
  - `createdAt`

### Repository Methods

Add repository helpers such as:

- `loadGuardianConfig(sessionID:)`
- `loadGuardianConfigs(directory:)`
- `saveGuardianConfig(directory:config:)`
- `deleteGuardianConfig(sessionID:)`
- optional `appendGuardianDecisionLog(...)`

## App State Changes

`OpenCodeAppModel` should expose guardian config in a way the session UI can bind to.

Suggested additions:

- `guardianConfigBySession: [String: GuardianConfiguration]`
- `setGuardianEnabled(_:for:)`
- `updateGuardianInstructions(_:for:)`
- `setGuardianQuestionHandling(_:for:)`
- `setGuardianFollowUpHandling(_:for:)`

The app state can remain the owner of editing and persistence, while the background coordinator owns automatic interventions.

## Coordinator Integration

### Where It Lives

Best fit is a sibling to `WorkspaceSyncCoordinator`.

Why:

- `WorkspaceSyncCoordinator` should stay focused on mirroring OpenCode state
- guardian logic is local product behavior layered on top of synced state
- keeping them separate makes it easier to test and to disable guardians cleanly

Suggested shape:

```swift
actor GuardianCoordinator {
    func updateConfiguration(_ configuration: GuardianConfiguration?)
    func handleInteractionsChanged(sessionID: String) async
    func handleStopEvent(_ event: GuardianStopEvent) async
}
```

### How It Gets Notified

Recommendation:

- trigger explicitly from the sync/update path rather than building another observer graph

In practice:

- after `WorkspaceSyncCoordinator.refreshInteractions(...)` updates the store, notify the guardian coordinator for the affected session
- when `WorkspaceSyncCoordinator` applies a `.stepFinish` part in `message.part.updated`, notify the guardian coordinator with a `GuardianStopEvent`

That keeps the control flow deterministic and testable.

## Auditability

Since we cannot create real server-side guardian child sessions, we need local audit state.

Recommended V1:

- log guardian decisions with `Logger(subsystem: "ai.opencode.app", category: "guardian")`
- optionally persist a lightweight local decision log

Suggested log fields:

- `sessionID`
- trigger type and trigger id
- action type
- prompt or answer summary
- failure reason if any

This gives us inspectability without pretending the guardian is an OpenCode-native session.

## Safety Rules

- guardian is disabled by default
- guardian never handles permissions
- guardian only uses local visible context
- if the decision engine is uncertain, defer to the user
- if reply submission fails, leave the question pending
- if follow-up prompt send fails, do not retry in a tight loop
- guardian logic must be idempotent per question id and per stop event id
- tests must use fakes or deterministic rules; never call real model providers

## Testing Strategy

Given the repo guidance, tests must not incur inference cost.

Required tests:

- guardian-disabled sessions do nothing on questions or stops
- guardian-enabled sessions answer eligible questions once
- guardian-enabled sessions never answer permissions
- duplicate interaction refreshes do not cause duplicate replies
- a new `stepFinish` stop event can trigger one follow-up prompt
- stop events with `reason == "tool-calls"` do not trigger follow-up prompts
- `maxFollowUpsPerTurn` prevents loops
- persistence round-trip restores guardian config across relaunch
- send/reply failures are logged and do not spin forever

If a model-backed engine is added later, it must be hidden behind `GuardianDeciding` and tested with a fake implementation.

## Implementation Plan

### Phase 1: Local Config Plumbing

- add guardian config Core Data entity
- add repository load/save APIs
- expose guardian config through `OpenCodeAppModel`
- add session UI controls

### Phase 2: Guardian Question Handling

- add `GuardianCoordinator`
- wire it to interaction refresh completions
- implement deterministic question-answer logic
- call existing `replyToQuestion(...)`

### Phase 3: Guardian Stop Handling

- detect `stepFinish` stop candidates from message part updates
- implement deterministic continuation logic
- send follow-up prompts with existing `sendMessage(...)`
- add loop prevention state and tests

### Phase 4: Polish And Observability

- add guardian logger and optional audit persistence
- surface guardian actions in UI if helpful
- add a debug affordance for the last guardian decision

## Open Questions

- Should stop evaluation run immediately on `stepFinish`, or after a short debounce window?
- Should guardian follow-up prompts be visibly tagged in the local UI as guardian-generated?
- Should a guardian-generated prompt be added to local audit only, or also mirrored into draft/history affordances for the user?
- How conservative should the initial continuation heuristics be when todos remain but the assistant appears complete?

## Recommendation

Yes, this can still be done purely on the Swift side, with broader scope than question handling.

The best client-only version is:

- local, opt-in, per-session guardian configuration
- observes synced visible session state already available in the app
- answers `question.asked` when possible
- evaluates stop events and can continue the run with one follow-up prompt when necessary
- never handles permissions
- persists its own config and audit data locally

The key tradeoff is that this is still a client-side supervisory layer, not a true OpenCode-native subagent. But within that constraint, it can influence the session in exactly the two places the current API allows: question replies and follow-up prompts.
