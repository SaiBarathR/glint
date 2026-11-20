# Architecture

Glint is two parts. One is a Swift package that holds everything that can be tested without a GUI. The other is an AppKit/SwiftUI app around it.

```
Packages/GlintCore/      extension engine (library + tests, depends on Yams)
App/Sources/             the app
  Core/                  AppDelegate (coordinator), Preferences, ActionRegistry, status item
  Selection/             global input monitor, selection reader (Accessibility + ⌘C fallback)
  Popup/                 the non-activating action bar: panel, item views, controller, offscreen snapshots
  Actions/               ActionBuilder (what appears for a selection), ActionPerformer (runs actions), Speech
  Support/               AX helpers, Clipboard, KeySender + KeyLayout, HotKeyCenter, IconRenderer, YAMLHelper
  Settings/              SwiftUI settings window and onboarding
  Updates/               GitHub release check
App/Resources/Extensions bundled extensions (loaded as trusted)
gallery/                 extra extensions offered on the website
site/                    the website (GitHub Pages)
```

## From a selection to a result

1. **SelectionMonitor** watches global mouse and keyboard events. It reports a trigger: a drag, a double- or triple-click, a shift-click, a long press, a keyboard selection or a hotkey.
2. **SelectionReader** asks the focused element for its selected text through Accessibility. Web views use text markers. If that returns nothing, and the gesture looked like a text selection, it sends ⌘C and restores the clipboard afterwards. It also reads whether the field is editable, whether Bold/Cut/Paste are available, and where the selection is on screen.
3. **ActionBuilder** turns the ordered, enabled registry entries into bar buttons. Built-ins decide for themselves when they apply. Extension actions go through `RequirementEvaluator` (requirements, regex, app filters).
4. **PopupController** shows the bar above or below the selection, pages it if it's too wide, and handles results, ✓/✗ and choices.
5. **ActionPerformer** runs built-ins directly and extensions through `ExtensionRuntime`. A `SessionHost` ties each running action to its selection. A late result is copied rather than pasted once the user has moved on.

## Extension engine (GlintCore)

- `Manifest.swift`: normalises config keys, so PopClip-style keys work too, and parses actions and options.
- `ExtensionLoader.swift`: loads bundles, single files and snippets, installs snippets, and picks safe folders. Untrusted YAML goes through `isolatedYAMLParser`. The app sets that to `YAMLHelper`, which parses in a child process (`Glint --parse-yaml`) with a deadline.
- `ExtensionRuntime.swift`: runs an action and applies `after`. It also builds shell environments, which are size-capped, and expands dynamic JavaScript actions.
- `ScriptRunner.swift`: runs shell scripts (async stdin, timeouts, SIGKILL), AppleScript (via `osascript`) and Shortcuts.
- `JavaScriptRunner.swift`: JavaScriptCore with the `glint` API, time limits, a sandbox for pre-install evaluation, and `require` with a module cache.

## Debug flags

| Flag | Does |
| --- | --- |
| `--render-bar <dir>` | Writes PNGs of the bar in every size, theme and mode, then exits |
| `--render-settings <dir>` | Writes PNGs of every settings pane and the onboarding window, then exits |
| `--demo-bar "<text>"` | Shows the real bar for a fake selection at the centre of the screen |
| `--parse-yaml` | Helper mode: reads YAML on stdin, prints JSON, exits (used by the app itself) |
