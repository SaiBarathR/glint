---
title: Getting started
description: Install Glint, make your first selection, and find your way around its settings, shortcuts and modifier keys.
---

# Getting started

Glint puts a small bar of actions next to the text you select, in any app. This page covers installing it, what
happens when you select text, and the settings worth knowing about.

## Install

1. [Download Glint](/glint/download/), unzip it and move **Glint.app** to Applications.
2. Open it. The first time, macOS blocks it because it isn't notarized: go to **System Settings → Privacy & Security**
   and click **Open Anyway** (on macOS 14 you can Control-click the app and choose **Open** instead).
3. Allow **Accessibility** access when the welcome window asks. Glint uses it to read the selection, find where it is
   on screen, and paste results.

The [download page](/glint/download/) has the details, including checking the archive and what to do after an update.

Glint lives in the menu bar and has no Dock icon. Its menu has:

| Item | What it does |
| --- | --- |
| **Pause Glint** / **Resume Glint** | Stop showing the bar everywhere, until you resume. |
| **Disable in *App*** / **Enable in *App*** | Turn Glint off (or on again) for the app in front. |
| **Settings…** <kbd>⌘</kbd><kbd>,</kbd> | Open Settings. |
| **Extensions…** | Open Settings at the Actions pane. |
| **Extension Log** | Output and errors from extensions, for when one doesn't do what you expect. |
| **Check for Updates…** | Ask GitHub for a newer release now. |
| **Quit Glint** <kbd>⌘</kbd><kbd>Q</kbd> | Quit. |

When Accessibility access is missing, the menu shows **Grant Accessibility Access…** at the top. When a newer release
exists, it shows **Update Available**.

## Your first selection

Select a word on a web page, a sentence in Notes or a path in Terminal. When you let go of the mouse, the bar appears
just above the selection. Click an action to run it. To dismiss the bar, click somewhere else, type, scroll, or move
the mouse away from it.

What you see depends on what you selected and where:

- **Cut** and **Paste** only appear where you can edit text.
- **Open Link** appears when the selection contains a URL, **New Email** for an email address, **Call** for a phone
  number, and **Reveal in Finder** for a file path that exists.
- **Calculate** appears when the selection is an arithmetic expression such as `12 * (3 + 4)`.
- **Spelling** appears for a misspelled word in editable text.
- **Install Extension** appears when the selection is an extension snippet: text whose first line is `#glint`.

Actions that produce a result, like Change Case or Calculate, replace the selection when it's editable. In text you
can't edit, they copy the result instead and show ✓. Some show their result in the bar; click it to copy it.

## Ways to bring up the bar

Glint shows the bar after any of these. Each can be switched off in **Settings → General → Show the Bar After**:

| Trigger | Notes |
| --- | --- |
| Selecting with the mouse | Drag across text. |
| Double-click | Selects a word. |
| Triple-click | Selects a line or paragraph. |
| Shift-click | Extends the current selection. |
| Selecting with the keyboard | ⇧ with the arrow keys, or ⌘A. Off by default. |
| Long press in a text field | Shows a Paste bar when nothing is selected. |

Glint works in apps that share their selection through the Accessibility API, which is most of them. For apps that
don't, it briefly presses ⌘C to read the selection and puts your clipboard back afterwards. You can turn that off in
**Settings → Advanced → Copy the selection when an app doesn't share it**.

## Keyboard shortcuts

- **Show bar shortcut** (Settings → General): shows the bar for the current selection from any app, even when the
  automatic triggers are off. There is no default; click the field and press the keys you want.
- **Per-action shortcuts** (Settings → Actions, then pick an action): run that action on the current selection without
  opening the bar. Built-in actions and extensions both have one.
- **Hold to suppress** (Settings → General): hold this key (⌥, ⌃, ⌘ or ⇧) while you select, and the bar stays hidden
  that time.

## Modifier keys

Hold a modifier while clicking an action to change what it does:

| Key | Effect |
| --- | --- |
| <kbd>⇧</kbd> Shift | Copy the result instead of pasting it. For links and web searches, copy the URL instead of opening it. On **Copy**, add to what's already on the clipboard. |
| <kbd>⌘</kbd> Command | Open URLs in the background, without bringing the browser to the front. |
| <kbd>⌥</kbd> Option | The action's alternate behaviour: the alternate URL of a search (GitHub code search, Google Maps), plain-text paste on **Paste**, descending order in **Sort Lines**. |

Extensions can read the held modifiers too and add their own alternate behaviour.

## Settings tour

Open Settings from the menu bar icon, or open Glint again while it's running.

### General

Turn Glint on or off, launch it at login, hide the menu bar icon (open Glint again to get back to Settings), and the
daily update check. **Permissions** shows whether Accessibility access is on. **Show the Bar After** has the triggers
above, and **Behavior** has the suppress key, a delay before the bar shows, and the show-bar shortcut.

<figure>
  <img class="screenshot theme-light-only" src="/glint/images/settings-general-light.webp" width="1520" height="1176" alt="Settings, General pane: Enable Glint, Launch at login, Show menu bar icon, Accessibility access is on, and the Show the Bar After triggers" loading="lazy" decoding="async" />
  <img class="screenshot theme-dark-only" src="/glint/images/settings-general-dark.webp" width="1520" height="1176" alt="Settings, General pane in dark mode" loading="lazy" decoding="async" />
</figure>

### Appearance

Show icons, text, or both; small, medium or large; light, dark or matching the system; above or below the selection.
**Show labels on hover** names an icon when you point at it, and **Hide when the mouse moves away** dismisses the bar
when you move on (otherwise it stays until you click elsewhere or press a key). A live preview sits at the top.

### Actions

Every built-in action and extension in the order they appear on the bar. Switch them on or off and drag to reorder.
Select one to see its settings:

- **Search** lets you pick the search engine: Google, DuckDuckGo, Bing, Kagi, Brave Search, Ecosia, Perplexity,
  Startpage, or a custom URL with `***` where the text goes.
- **Speak** has a voice picker with a sample.
- Extensions show their description, author and identifier, their own options (passwords and API keys go in the macOS
  Keychain), a keyboard shortcut, **Show in Finder** and **Uninstall…**.

The **+** menu has **Install from File…**, **Paste Snippet…**, **Open Extensions Folder**, **Reload Extensions** and
**Reset Order**. Extensions that fail to load are listed at the top with the reason.

### Apps

Apps where Glint never appears. Password managers (1Password, Bitwarden), Keychain Access, the login window and Screen
Sharing are on the list by default. Add others with **+**, or use **Disable in *App*** from the menu bar menu while the
app is in front.

<figure>
  <img class="screenshot theme-light-only" src="/glint/images/settings-apps-light.webp" width="1520" height="1176" alt="Settings, Apps pane: the Excluded Apps list with 1Password, Keychain Access, Bitwarden, loginwindow and Screen Sharing" loading="lazy" decoding="async" />
  <img class="screenshot theme-dark-only" src="/glint/images/settings-apps-dark.webp" width="1520" height="1176" alt="Settings, Apps pane in dark mode" loading="lazy" decoding="async" />
</figure>

### Advanced

The copy fallback for apps that don't share their selection, the most text Glint reads at once (100,000 characters by
default), **Restore the clipboard after pasting**, shortcuts to the Accessibility and Automation settings, and
**Reset all settings** (installed extensions are kept).

### About

The version, an update check, and links to the project.

## Extensions

Glint comes with 28 extensions: Translate (on by default), Change Case, Sort Lines, Format JSON, Base64, web searches
and more. Turn them on in **Settings → Actions**. The [extensions page](/glint/extensions/) lists them, along with a
gallery of more you can install in one click.

To write your own, start with [Writing extensions](/glint/docs/writing-extensions/).

## Troubleshooting

**The bar doesn't appear.** Check that Accessibility is on in **System Settings → Privacy & Security →
Accessibility**. After updating Glint, switch it off and on again; if it already looks on, remove Glint with **−** and
add it again. Also check that Glint isn't paused, and that the app isn't in **Settings → Apps**.

**The bar appears, but not in one app.** Some apps don't share their selection. Make sure **Copy the selection when an
app doesn't share it** is on in Settings → Advanced, or use the show-bar shortcut.

**An extension shows ✗.** Open **Extension Log** from the menu bar menu to see its error output.
