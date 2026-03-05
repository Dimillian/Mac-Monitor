# MacMonitor Agent Guide

All docs in this repo should describe current behavior only.

## Scope

This file is the contributor contract for working on MacMonitor itself.

Primary references:

- `README.md` (setup + run workflow)
- `Project.swift` (Tuist manifest + app target config)
- `run-menubar.sh` (canonical local launch flow)

## Project Snapshot

MacMonitor is a macOS menubar app that embeds a Codex conversation UI and
basic machine telemetry.

Current stack:

- App UI/runtime: SwiftUI + Observation (`Sources/**`)
- App-server transport: custom JSON-RPC actor over stdio (`Sources/Client/**`)
- Build/generation: Tuist (`Project.swift`)
- Launch workflow: shell launcher (`run-menubar.sh`)

## Non-Negotiable Architecture Rules

1. Keep the app menubar-only (`LSUIElement = true`) unless product direction changes.
2. Keep app-server/network transport logic in `Sources/Client`, not in view bodies.
3. Keep thread/session state transitions in store layer (`Sources/Store`), not in views.
4. Keep view files render-focused and side-effect light.
5. Treat Tuist manifests as source of truth; do not rely on generated Xcode artifacts.

## Routing Rules (Code Placement)

App-server behavior:

1. `Sources/Client/CodexAppServerSession.swift` (JSON-RPC transport and event parsing)
2. `Sources/Store/ConversationStore.swift` (thread lifecycle, streaming message state, approvals)

Telemetry behavior:

1. `Sources/Store/MacSystemStore.swift` (collection + snapshot policy)
2. `Sources/Models/AppModels.swift` (shared data models)

UI behavior:

1. `Sources/App/MacMonitorApp.swift` (scene wiring only)
2. `Sources/Views/MenuBarConversationView.swift` (top-level menu panel)
3. `Sources/Views/SystemStatusView.swift` / `Sources/Views/MessageRowView.swift` (subviews)

## Key File Anchors

- Tuist manifest: `Project.swift`
- App entrypoint: `Sources/App/MacMonitorApp.swift`
- App-server client: `Sources/Client/CodexAppServerSession.swift`
- Conversation store: `Sources/Store/ConversationStore.swift`
- System store: `Sources/Store/MacSystemStore.swift`
- Menu UI: `Sources/Views/MenuBarConversationView.swift`
- Runtime agent instructions resource: `Resources/AGENTS.md`
- Launch scripts: `run-menubar.sh`, `stop-menubar.sh`

## Runtime and Launch Invariants

- `run-menubar.sh` is the canonical local run path.
- Launcher must stop an existing app instance before relaunch.
- Launcher must not open Xcode as a side effect.
- Keep `.app` launches functional (bundled runtime instructions required).

## Safety and Git Behavior

- Prefer safe git operations (`status`, `diff`, `log`).
- Do not reset/revert unrelated user changes.
- If unrelated changes appear, continue in scoped files unless correctness is blocked.
- Fix root cause over UI-only band-aids.

## Validation Matrix

Run validations based on touched areas:

- Always after code changes:
  - `TUIST_SKIP_UPDATE_CHECK=1 tuist build MacMonitor --configuration Debug`
- If scripts changed:
  - `bash -n run-menubar.sh`
  - `bash -n stop-menubar.sh`
- If launch flow changed:
  - `./run-menubar.sh`

## Quick Runbook

```bash
# Build only
TUIST_SKIP_UPDATE_CHECK=1 tuist build MacMonitor --configuration Debug

# Canonical local run
./run-menubar.sh
```

