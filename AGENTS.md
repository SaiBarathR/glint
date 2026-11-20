# AGENTS.md

The repository contract for anyone (human or agent) changing Glint. Read it before each work cycle.

## What Glint is

A native macOS menu-bar app (Swift, AppKit + SwiftUI, macOS 14+). When you select text in any app, a small action bar appears next to it. Actions are built-ins or extensions run by the `GlintCore` package. See `docs/architecture.md`.

## Build and test

```bash
brew install xcodegen                         # once
swift test --package-path Packages/GlintCore  # engine tests (fast, no GUI)
./scripts/build-app.sh --native               # dist/Glint.app for this Mac
./scripts/build-app.sh --dev-sign --install   # keep Accessibility across rebuilds while developing
```

`Glint.xcodeproj` is generated from `project.yml` by XcodeGen and isn't committed. Re-run `xcodegen generate` after adding files.

## Rules

- **Keep the engine testable.** Logic that doesn't need AppKit goes in `Packages/GlintCore` with tests. Every bug fix gets a regression test when it can.
- **Untrusted input:** snippets, `glint://` links, opened bundles/zips and user extensions are untrusted. YAML from them is parsed out of process (`YAMLHelper`). No extension JavaScript runs before the user agrees to install (`evaluateModules: false` for prompts). Keep both properties.
- **The user's clipboard is sacred.** Every temporary write is restored, and a user's own copy always wins (see `Clipboard.swift`).
- **Never touch real user data in tests or experiments:** not the real `~/Library/Application Support/Glint/Extensions`, the clipboard, the Keychain or the Trash. Use temp directories or a scratch disk image. Delete any crash reports your experiments cause.
- **UI quality:** nothing overlapping or clipped, proper padding, text never touching borders, light and dark mode. Check UI changes with `--render-bar` / `--render-settings` screenshots and look at them before calling a change done.
- **Extensions docs:** `docs/EXTENSIONS.md` is the single source of truth for the extension format. The website renders it, so keep it accurate when the engine changes.
- **Branding:** Glint is independent. It can read PopClip's extension format for compatibility, but never use PopClip's name, icons, copy or extension texts as Glint's own.

## Releases

Tag-driven via GitHub Actions; see `docs/releasing.md`. Bump `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml`, and write `docs/releases/vX.Y.Z.md`.

## Commits

Small, focused commits with a summary line in the imperative and a body saying why. Run `swift test` and build before pushing. CI must stay green.
