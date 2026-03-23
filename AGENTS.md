# App Logging Notes

# Testing

- Tests must never incur real model or inference cost.
- Do not call real model providers, paid APIs, or live inference endpoints from the test suite.
- Prefer mocks, fakes, fixtures, and local test doubles for any model-facing behavior.
- If code is hard to test without live inference, add or refine abstractions so model interactions can be injected and mocked.

- Use `Logger(subsystem: "ai.opencode.app", category: "your-category")` from `OSLog`.
- Prefer `.notice` for temporary diagnostics you want to inspect with `log show`.
- To inspect logs from the running app:

```bash
/usr/bin/log show --last 10m --style compact --info --predicate 'process == "OpenCode" && subsystem == "ai.opencode.app" && category == "your-category"'
```
