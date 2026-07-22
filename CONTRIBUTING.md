# Contributing to Agent Controller

Thanks for helping make controller-first agent workflows better on macOS.
Focused issues and pull requests are welcome.

## Before you start

Agent Controller treats controller input as semantic intent. New behavior
should enter through a typed action and a scoped adapter—not a button wired
directly to an app-specific shortcut.

Please open an issue before proposing any action that can approve, reject,
send unattended input, execute shell commands, modify external state, or
perform destructive work. Those changes need an explicit safety contract.

## Development setup

You need macOS 14 or newer and a Swift 6.1 toolchain.

```bash
swift test --disable-sandbox
swift build --disable-sandbox
scripts/build-app.sh
```

For controller or UI changes, run the built app and verify the affected flow
with a physical controller. State clearly when hardware, microphone, or live
Codex proof was unavailable.

## Pull requests

Keep each pull request narrow and explain:

- what behavior changed;
- why the change belongs at the semantic, adapter, or presentation layer;
- which automated checks passed;
- which physical or live checks were performed or remain blocked.

Before opening a pull request, run:

```bash
scripts/check-source-size.sh
swift test --disable-sandbox
swift build --disable-sandbox
```

Every Swift source and test file must stay at or below 500 lines.

## Privacy

Never attach real prompts, task titles, project paths, accessibility trees,
keystrokes, clipboard contents, credentials, or other user content to issues,
fixtures, logs, or screenshots. Use synthetic examples and redact local
identifiers before sharing diagnostics.
