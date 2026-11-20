---
title: Safety and limits
description: What Glint checks before an extension runs, how untrusted configs are read, and the size and time limits extensions work within.
---

# Safety and limits

Extensions can run scripts on your Mac, so Glint treats every extension that didn't ship with it as untrusted until you
decide otherwise. This page describes what that means in practice, and the limits extensions run within. The numbers
come from Glint's engine (`Packages/GlintCore`) and are the same for snippets, install links, folders and zips.

## Before you install

Snippets you select, `glint://install` links, and `.glintext` / `.glintextz` files you open are all **untrusted**:

- **Glint asks first.** The install prompt shows the extension's name, description and the kinds of actions it has
  (URL, shell script, AppleScript, JavaScript and so on), and reminds you to install only from people you trust.
- **No code runs before you agree.** The prompt is built from the static config only. JavaScript modules are not
  evaluated, so a `Config.js` extension shows its name and nothing else until you install it.
- **Configs are read out of process.** YAML from untrusted sources is parsed by a separate helper process with a
  3-second deadline, so a malformed or hostile document can't hang or crash Glint.
- **Nothing is replaced silently.** Installing never overwrites a different extension that happens to use the same
  folder name; the new one goes into `<name>-2`.

## Config limits

| Limit | Value |
| --- | --- |
| Config file size (YAML, JSON or property list) | 256 KB |
| YAML size, counted in nodes after aliases are expanded | 50,000 nodes |
| YAML alias references (`*name`) | 24 |
| Actions in one extension | 200 |

YAML keys must be plain text, duplicate keys are an error, and values such as `yes`, `on` or `1:00:00` stay text rather
than turning into booleans or numbers.

## Running

| What | Limit |
| --- | --- |
| Shell scripts | 30 seconds, then the script is stopped and the action fails |
| AppleScript | 120 seconds, in a separate `osascript` process, so dialogs and first-run Automation prompts never block Glint |
| JavaScript promises | 30 seconds |
| `sleep()` in JavaScript | at most 10 seconds per call |
| Reading a JavaScript module's config, including before install | sandboxed: no network, no timers, 1 second |
| Building dynamic actions while the bar opens | sandboxed, 0.5 seconds |
| Shell environment | any single value over 64 KB is left empty, and the whole environment stays under about 384 KB; the full text is always on stdin |

JavaScript runs in a fresh JavaScriptCore context for every action, and `require` only loads files from inside the
extension's own folder.

## Your clipboard

Pasting a result goes through the clipboard. Glint puts back what was there afterwards (**Settings → Advanced →
Restore the clipboard after pasting**), and if you copy something yourself while an action is running, your copy wins.
The same goes for the copy fallback Glint uses in apps that don't share their selection.

## Where your text goes

Glint has no account, server or analytics. Your selection only leaves your Mac when you run an action that sends it
somewhere, such as a web search or an extension that calls a web API. The optional daily update check asks GitHub's
public releases API for the latest version and sends nothing else.

Password managers, Keychain Access, the login window and Screen Sharing are excluded by default, so the bar never reads
selections there. Add other apps in **Settings → Apps**.

Option values marked `password` or `secret` are stored in the macOS Keychain, not in Glint's preferences.

## Reporting a problem

If you find a way around any of this, please open an issue on [GitHub](https://github.com/SaiBarathR/glint/issues).
