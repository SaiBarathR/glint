# Contributing to Glint

Thanks for helping. Bug reports, extension ideas and pull requests are all welcome.

## Reporting a bug

Open an issue and include:
- your macOS version and Mac (Apple silicon or Intel), and the Glint version (Settings → About);
- the app you were selecting text in, and what you expected to happen;
- for extension problems, the extension's config and anything in **Extension Log** (menu bar menu).

## Sharing an extension

The easiest way is a snippet. Paste it into an issue, or open a pull request that adds it to `gallery/`, where the website picks it up. `docs/EXTENSIONS.md` describes the format. Gallery extensions get a test in `Packages/GlintCore/Tests/GlintCoreTests/GalleryExtensionsTests.swift`.

## Changing the app

1. Read `AGENTS.md`, the repository contract.
2. `brew install xcodegen`, then `swift test --package-path Packages/GlintCore` and `./scripts/build-app.sh --native`.
3. Keep changes focused, add tests for engine changes, and check UI changes with `--render-bar` / `--render-settings` screenshots.
4. Open a pull request describing what changed and why. CI must pass.

By contributing you agree that your contributions are licensed under the MIT License.
