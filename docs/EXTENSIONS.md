# Writing Glint extensions

An extension adds one or more **actions** (buttons) to Glint's bar. Each action does one thing with the
selected text: it opens a URL, runs a shell script, AppleScript or JavaScript, presses keys, or calls a
macOS Service or a Shortcuts shortcut. It can then paste, copy or show the result.

This reference follows the engine in `Packages/GlintCore` (`Manifest.swift`, `ExtensionLoader.swift`,
`Requirements.swift`, `Templates.swift`, `ExtensionRuntime.swift`, `ScriptRunner.swift`,
`JavaScriptRunner.swift`). The bundled extensions in `App/Resources/Extensions` are working examples of
every format described here.

- [Forms an extension can take](#forms-an-extension-can-take)
- [Config keys](#config-keys)
- [Action kinds](#action-kinds)
- [Requirements and regex](#requirements-and-regex)
- [After: what happens to the result](#after-what-happens-to-the-result)
- [Modifier keys](#modifier-keys)
- [Options](#options)
- [URL and AppleScript placeholders](#url-and-applescript-placeholders)
- [Shell scripts](#shell-scripts)
- [JavaScript](#javascript)
- [Icons](#icons)
- [Installing, identifiers and debugging](#installing-identifiers-and-debugging)
- [Compatibility notes](#compatibility-notes)

---

## Forms an extension can take

### 1. YAML snippet

Text whose first non-empty line is a `#glint` header, followed by YAML config. Select it anywhere and
click **Install Extension**.

```yaml
#glint
name: Search MDN
icon: symbol:book
url: https://developer.mozilla.org/en-US/search?q=***
```

The header line may carry config of its own (`#glint name: Foo`), and `#popclip` / `# popclip` headers
are accepted too.

### 2. Inverted snippet (code first)

The config sits in comment lines at the top of a script, after a commented header such as `// #glint`.
Every following line that starts with the same comment prefix is config. The first line without it starts
the code.

```js
// #glint
// name: Reverse
// after: paste-result
return glint.input.text.split('').reverse().join('');
```

```sh
# #glint
# name: Line Count
# after: show-result
wc -l | tr -d ' '
```

```applescript
-- #glint
-- name: Say It
say "{glint text}"
```

Recognised comment prefixes are `//`, `#`, `--`, `;` and `%`. Without a `language` key, the language is
guessed from the prefix: `//` means JavaScript, `--` means AppleScript, and anything else is a shell script.
Set `language` to choose:

| `language` | Runs as |
| --- | --- |
| `javascript`, `js` | JavaScript (in Glint's JavaScriptCore runtime) |
| `applescript` | AppleScript |
| `shell`, `sh` → `/bin/sh`; `bash` → `/bin/bash`; `zsh` → `/bin/zsh` | shell |
| `python`, `python3`, `ruby`, `perl`, `node`, `nodejs`, `swift`, `php` | that interpreter, found on `PATH` through `/usr/bin/env` |
| anything else | used verbatim as the interpreter command |

A JavaScript inverted snippet becomes a **module** when it sets `module: true` or when its code contains
`exports.actions`, `exports.action ` or `module.exports` (see [JavaScript modules](#javascript-modules)).

### 3. Single YAML file

A `.yaml` / `.yml` file holding the config dictionary (no header needed). `.txt` files are loaded too, and
are read as snippets when they start with a `#glint` header. Glint's bundled extensions use this form for
most simple actions.

### 4. Bundle folder

A folder named `Name.glintext` (`.popclipext` also works) containing a config file plus any scripts,
modules and images it references. The config file is the first of these that exists:

`Config.yaml`, `Config.yml`, `Config.json`, `Config.plist`, `config.yaml`, `config.yml`, `config.json`,
`config.plist`, `Config.js`, `Config.ts`, `config.js`

YAML, JSON and property-list configs share the same keys. `Config.js` defines the whole extension in
JavaScript (see [JavaScript modules](#javascript-modules)). A folder holding a `Snippet.txt` is loaded as
that snippet. Installing a snippet creates exactly such a folder.

---

## Config keys

**Key names are normalised**: case, spaces, underscores and hyphens are ignored, so `Shell Script File`,
`shell_script_file`, `shell-script-file` and `shellScriptFile` all mean the same key. The tables list
alternative names after the main one.

### Extension keys

| Key | Meaning |
| --- | --- |
| `name` (`extension name`, `title`) | **Required.** Display name, also the default action title. |
| `identifier` (`extension identifier`) | Unique ID in reverse-DNS form, e.g. `com.example.shout`. See [identifiers](#installing-identifiers-and-debugging). |
| `description` (`extension description`) | Shown in Settings. |
| `icon` (`image file`, `extension image file`) | Default icon for every action. See [Icons](#icons). |
| `author` (`credits`) | Shown in Settings. |
| `homepage` (`app link`, `link`) | Shown in Settings. |
| `options` | List of user settings. See [Options](#options). |
| `actions` | List of action dictionaries. Without it, the extension's own dictionary is read as its single action. |

### Action keys

| Key | Meaning |
| --- | --- |
| `title` (`name`) | Button title (tooltip / text label). Defaults to the extension name. |
| `icon` (`image file`) | Defaults to the extension icon. |
| `identifier` | Optional ID for the action (informational; hotkeys, ordering and enable state apply to the whole extension). Defaults to its index. |
| *one action kind* | See [Action kinds](#action-kinds). An action dictionary with no kind is ignored. |
| `requirements` (`required`) | When the action is offered. Default `[text]`. See [Requirements](#requirements-and-regex). |
| `regex` | Only offer the action when this regular expression matches; the match becomes the input. |
| `after` | What to do with the result. See [After](#after-what-happens-to-the-result). |
| `paste result` / `copy result` / `show result` | Legacy booleans, used only when `after` is absent. |
| `required apps` (`apps`, `app`) | Only offer the action in these apps (bundle IDs). |
| `excluded apps` (`blocked apps`) | Never offer the action in these apps. |
| `stay visible` | Keep the bar open after the action runs (default `false`). |
| `restore pasteboard` (`restore clipboard`) | After `paste-result`, put the previous clipboard contents back. |
| `trim` | Trim whitespace and newlines from both ends of the selection before running (default `true`). Set `false` to receive the exact selection. |
| `capture html` | Ask for the selection's HTML as well, which the action reads as `GLINT_HTML` / `glint.input.html`. When the action runs, Glint copies the selection (restoring the clipboard afterwards) to get the HTML from apps that provide it. |
| `interpreter` | Shell interpreter for `shell script` / `shell script file`. See [Shell scripts](#shell-scripts). |
| `description` | Per-action description. |

**Inherited defaults.** These keys may also be set at the extension level, and then apply to every action
that doesn't set its own: `requirements`, `regex`, `after`, `required apps` (also `required app bundle
identifiers`), `excluded apps` (also `excluded app bundle identifiers`), `stay visible`,
`restore pasteboard`, `capture html` and `interpreter`. `trim` is per-action only.

App lists can be a single string, a list of strings, a list of dictionaries with a `bundle identifier`
key, or a dictionary with `bundle identifiers`:

```yaml
required apps: [com.apple.Safari, com.google.Chrome]
excluded apps: com.apple.Terminal
```

### Multiple actions in one extension

```yaml
name: Dictionary
icon: symbol:character.book.closed
requirements: [text, '!url']     # inherited by both actions
actions:
  - title: Define
    url: https://www.dictionary.com/browse/***
  - title: Synonyms
    icon: symbol:arrow.triangle.swap
    url: https://www.thesaurus.com/browse/***
```

---

## Action kinds

When an action dictionary holds several of these keys, the first one in this order wins:

| Key | Action |
| --- | --- |
| `url` | Open a URL template. `alternate url` (`alt url`) is used instead while ⌥ is held. |
| `shell script` | Run inline shell source. |
| `shell script file` (`script file`) | Run a script file from the bundle folder. |
| `applescript` (`apple script`) | Run inline AppleScript (placeholders are filled in). |
| `applescript file` (`apple script file`) | Run an AppleScript file (`.applescript` or compiled `.scpt`) from the bundle. Placeholders are **not** filled in files. |

AppleScript runs in a separate `osascript` process with a 120-second timeout, so dialogs, `delay` and
first-run Automation prompts never block Glint. The result is the script's return value as text.
| `javascript` (`java script`) | Run inline JavaScript. |
| `javascript file` (`java script file`) | Run a JavaScript file from the bundle. A file that assigns `exports` is a one-action module. |
| `key combos` | Press several key combos in sequence (50 ms apart). |
| `key combo` (`keyboard shortcut`) | Press one key combo in the frontmost app. |
| `service name` (`service`) | Run a macOS Service by its menu title on the selection. |
| `shortcut name` (`shortcut`) | Run a Shortcuts.app shortcut with the selection as input. Its text output is the result. |
| `language` + code | Inverted snippets only: the code body, run in that language. |

Plus JavaScript **module actions** defined in code (`exports.actions`). See below.

### Key combos

A key combo is a string such as `command b`, `cmd+shift+k`, `option return`, `⌘⌥V` or `ctrl-a`, a raw
virtual key code number, or a dictionary `{key code: 11, modifiers: 1048576}` / `{key char: b, modifiers:
command}`. Numeric modifiers use the NSEvent bit layout (shift `131072`, control `262144`, option
`524288`, command `1048576`).

Modifier words: `command`/`cmd`/`meta`/`super`, `shift`, `option`/`opt`/`alt`, `control`/`ctrl`/`ctl`.
Keys: letters, digits, `= - ] [ ' ; \ , / . \``, and `return`/`enter`, `tab`, `space`, `delete`/`backspace`,
`forwarddelete`, `escape`/`esc`, `home`, `end`, `pageup`, `pagedown`, `left`/`right`/`up`/`down` (also
`arrowleft` and so on), `f1`–`f12`, `keypadenter`. Keys are named by the character they type (numeric key codes are read as positions on a US keyboard), and Glint presses whichever key types that character on your current layout, so `command x` is ⌘X on Dvorak, AZERTY or QWERTZ too.

```yaml
name: Strikethrough (Notes)
icon: symbol:strikethrough
required apps: com.apple.Notes
requirements: [formatting]
key combo: command shift x
```

---

## Requirements and regex

`requirements` is a list. **All** entries must be satisfied for the action to appear. Prefix an entry
with `!` to require the opposite (`'!url'` means "only when the selection is *not* a single URL"; quote it
in YAML).

| Requirement | Satisfied when |
| --- | --- |
| `text` | There is non-blank selected text. **This is the default.** |
| `copy` | There is text and it can be copied. |
| `cut` | There is text and it can be cut (editable). |
| `paste` | The target is editable and the clipboard holds text. |
| `editable` | The target is editable (can paste or cut). |
| `formatting` | The target accepts rich-text formatting (Bold/Italic/Underline). |
| `url` | The selection contains exactly one URL. The action's input becomes **that URL**. |
| `urls` | The selection contains at least one URL. |
| `email` | The selection contains exactly one email address. The input becomes **that address**. |
| `emails` | At least one email address. |
| `path` | A line of the selection is a path (`/…`, `~/…` or `file://…`) that exists on disk. |
| `html` | The selection's HTML is available: the app provided it, or the action sets `capture html` (the HTML is then fetched when the action runs). |
| `number` / `math` | The whole selection is an arithmetic expression Glint can calculate. |
| `none` or empty | Always satisfied. |

Unknown requirement names are ignored rather than hiding the action. `requirements: []` removes the
default `text` requirement entirely.

URLs are found with the system data detector plus bare domains like `example.com/page`, which get
`https://` added.

### regex

`regex` is an ICU regular expression (NSRegularExpression syntax) tested against the selection. The action
is hidden when it doesn't match. When it matches, the **first match** becomes the action's input
(`GLINT_TEXT`, `glint.input.text`, the text in URLs), and the capture groups are available as
`GLINT_REGEX_GROUP_0…n` and `glint.input.regexResult` (group 0 is the whole match).

To use a regex only as a filter while keeping the whole selection as input, match everything behind a
lookahead:

```yaml
# Offered only when the selection contains a %XX escape; the input is still the whole selection.
regex: '^(?=[\s\S]*%[0-9A-Fa-f]{2})[\s\S]*$'
```

The input text an action receives is, in order of precedence: the regex match, else the detected URL
(`url` requirement) or email (`email` requirement), else the selection trimmed (unless `trim: false`).

---

## After: what happens to the result

A script's **result** is a shell script's stdout (minus one trailing newline), AppleScript's return value,
a JavaScript return value or resolved promise, or a shortcut's text output. An empty result means "no
result".

| `after` | With a result |
| --- | --- |
| *(absent)* | Nothing. The action works by side effect. |
| `paste-result` | Replace the selection with the result. **Becomes `copy-result`** when ⇧ is held or the target isn't editable, so the same action works in read-only text. |
| `copy-result` | Copy the result to the clipboard and show ✓. |
| `show-result` | Show the result in the bar. |
| `preview-result` | Show the result in the bar; clicking it copies it. |
| `show-status` | Show ✓. With no result, `show-status` still shows ✓ after success. |

Values are normalised like keys, so `paste-result`, `pasteResult` and `Paste Result` are the same. In all
cases a **failure** shows ✗ and writes the error message to the extension console. Failures are a shell
exit status other than 0 and 2, an AppleScript error, or a thrown JavaScript error or rejected promise.
A shell exit status of **2** (or `glint.showSettings()` in JavaScript) opens the extension's settings
instead, which is useful when a required option is missing.

---

## Modifier keys

The modifiers held when an action is clicked are passed to every action (`GLINT_MODIFIER_FLAGS`,
`glint.modifiers`). The engine also applies these rules itself:

| Key | URL actions | Script actions |
| --- | --- | --- |
| ⇧ Shift | Copy the filled-in URL instead of opening it (shows ✓). | `paste-result` copies instead of pasting. |
| ⌘ Command | Open the URL in the background, without activating the browser. | — |
| ⌥ Option | Use `alternate url` when the action has one. | — (read `glint.modifiers.option` to add your own alternate behaviour) |

Flag values in `GLINT_MODIFIER_FLAGS` use the NSEvent bits: shift `131072`, control `262144`, option
`524288`, command `1048576`, added together.

---

## Options

`options` declares settings that appear in the extension's page in Settings. Their values reach the
action as placeholders, environment variables and `glint.options`.

```yaml
options:
  - identifier: lang
    label: Translate to
    type: multiple
    values: [en, fr, de]
    value labels: [English, French, German]
    default value: en
  - identifier: apikey
    label: API key
    type: secret
  - identifier: loud
    label: Shout the result
    type: boolean
    default value: false
```

| Key | Meaning |
| --- | --- |
| `identifier` (`id`, `option identifier`) | **Required.** Name used in placeholders, env vars and `glint.options`. |
| `type` (`option type`) | `string` (default), `boolean` (`bool`, `checkbox`), `multiple` (`choice`, `enum`, `select`), `password`, `secret`, `heading`. |
| `label` (`option label`) | Shown in Settings. Defaults to the identifier. |
| `description` (`option description`) | Help text under the field. |
| `default value` (`default`) | Initial value. Booleans become `"1"` / `"0"`. |
| `values` (`option values`) | Choices for `multiple`. |
| `value labels` (`option value labels`) | Display names for `values`, in the same order. |
| `inset` | Indent the option under the one above it. |
| `hidden` | Don't show it in Settings. |

- A value never set by the user takes the default. For `multiple`, that falls back to the first value.
- `password` and `secret` values are stored in the macOS Keychain, not in preferences.
- `heading` is a section title in Settings and has no value.
- In shell scripts and placeholders every value is a string (`"1"`/`"0"` for booleans). In JavaScript,
  boolean options are real `true`/`false`.

---

## URL and AppleScript placeholders

URL templates (`url`, `alternate url`) and **inline** AppleScript are filled in before running:

| Placeholder | Replaced with |
| --- | --- |
| `***` | The input text (**URLs only**). |
| `{glint text}` / `{popclip text}` | The input text. |
| `{glint option NAME}` / `{popclip option NAME}` | The value of option `NAME` (matched exactly, then case/space-insensitively; empty if unset). |
| `{glint url}` | The first URL found in the selection (empty if none). |
| `{glint urls}` | Every URL found, one per line. |
| `{glint html}` | The selection's HTML, when the app provided it (empty otherwise). |
| `{glint app name}` | Name of the app the text was selected in. |
| `{glint bundle identifier}` | Bundle identifier of that app. |

In URLs the values are percent-encoded for a query component, so put option values in the query or a
path segment, not a whole URL. Values are encoded (spaces become `%20`; `& + = ? # / : ; , @ $
! ' ( ) *` are escaped). In AppleScript they are escaped for a double-quoted string literal (`\` and `"`
are backslash-escaped), so always put the placeholder **inside quotes**:

```applescript
set theText to "{glint text}"
tell application "Reminders" to make new reminder with properties {name:theText}
```

Every placeholder also works with the `popclip` prefix. Shell scripts and JavaScript get no placeholder
substitution; they read the same values from environment variables or the `glint.*` API.

---

## Shell scripts

A shell action receives:

- **stdin**: the input text (UTF-8, no trailing newline added).
- **environment variables**, each available with both a `GLINT_` and a `POPCLIP_` prefix:

| Variable | Value |
| --- | --- |
| `GLINT_TEXT` | The input text (regex match / URL / trimmed selection). |
| `GLINT_FULL_TEXT` | The whole (trimmed) selection, before any regex or URL narrowing. |
| `GLINT_URLS` | URLs found in the selection, one per line. |
| `GLINT_REGEX_GROUP_0` … `_n` | Regex capture groups (when the action has a `regex`). |
| `GLINT_OPTION_<ID>` | Each option value. The ID is upper-cased and non-alphanumerics become `_` (`api-key` → `GLINT_OPTION_API_KEY`). |
| `GLINT_MODIFIER_FLAGS` | Held modifiers as an integer (see [Modifier keys](#modifier-keys)). |
| `GLINT_BUNDLE_IDENTIFIER`, `GLINT_APP_NAME` | The app the selection came from. |
| `GLINT_BROWSER_URL` | The page URL, when the selection came from a browser that exposes it. |
| `GLINT_HTML` | Selection HTML, when available (see `capture html`). |
| `GLINT_MARKDOWN` | Currently the plain selection text. |
| `GLINT_EXTENSION_IDENTIFIER`, `GLINT_EXTENSION_PATH` | This extension's ID and bundle folder. |
| `GLINT_TEXT_TRUNCATED` | `1` when the input was too large for the environment (see below), otherwise `0`. |

To keep the environment under macOS's size limit, any single value larger than 64 KB is left empty, and the
whole environment is kept under about 384 KB: when it would be larger, values are emptied in this order until
it fits: `GLINT_HTML`, `GLINT_MARKDOWN`, `GLINT_FULL_TEXT`, `GLINT_BROWSER_URL`, regex groups, `GLINT_URLS`, option values and,
last, `GLINT_TEXT`. The full input text is always on **stdin**, so scripts that may receive large selections
should read stdin.

- **PATH** is prefixed with `/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin`.
  `LANG` defaults to `en_US.UTF-8`.
- **Working directory**: the bundle folder (for bundles).
- **stdout** is the result (one trailing newline removed). **stderr** goes to the extension console.
- **Exit status**: `0` success, `2` open the extension's settings, anything else failure (✗, stderr is the message).
- **Timeout**: 30 seconds, after which the script is terminated and the action fails.

How the script is started:

1. With an `interpreter` key: an absolute path (`/bin/bash -e`) runs directly, and a bare name (`python3`,
   `node --no-warnings`) runs through `/usr/bin/env`. The script path is passed as the last argument.
2. Otherwise a `shell script file` that is executable runs directly.
3. Otherwise a `#!` line at the top of the script is honoured.
4. Otherwise `/bin/zsh` runs it.

```yaml
# Base64.glintext/Config.yaml
name: Base64
after: paste-result
actions:
  - title: Base64 Encode
    shell script file: encode.sh      # next to Config.yaml
```

```sh
#!/bin/sh
# encode.sh: the selection arrives on stdin
/usr/bin/base64 | tr -d '\n'
```

Prefer tools that ship with macOS. `python3` exists only once the Xcode Command Line Tools are installed.

---

## JavaScript

JavaScript runs in a fresh JavaScriptCore context for each action, with the API below. Glint's own
object is `glint`, and `popclip` is an alias of it.

### Inline scripts and files

`javascript:` source (or a `// #glint` snippet body) is evaluated as a script. You may use `return` at
the top level: if the source doesn't parse as a script, Glint wraps it in a function (an `async` one when
it contains `await`). The result is the value of the last expression or the returned value.

```yaml
name: URL Encode
after: paste-result
javascript: return encodeURIComponent(glint.input.text)
```

A `javascript file` runs the same way, unless it assigns `exports`/`module.exports`: then it's treated as
a module and its first action runs.

### Return values

| Returned | Result |
| --- | --- |
| string | that string |
| number / boolean | its string form |
| object / array | JSON text |
| `undefined` / `null` | no result |
| a Promise | awaited (30 s timeout); its value is used as above, and a rejection is a failure |
| *(throws)* | failure: ✗, and the message goes to the console |

### The `glint` API

**`glint.input`**

| Property | |
| --- | --- |
| `text` | The input text (regex match / URL / trimmed selection). |
| `matchedText` | Same as `text`. |
| `fullText` | The whole (trimmed) selection. |
| `regexResult` | Array of regex capture groups (`[0]` is the whole match). Empty without a `regex`. |
| `html` | Selection HTML or `""`. `isRichText` is `true` when HTML is available. |
| `markdown` | Currently the plain selection text. |
| `data.urls` / `data.webUrls` | URLs found in the selection. |
| `data.emails` | Email addresses found. |
| `data.paths` | Existing file paths found. |
| `data.nonHttpUrls` | Always empty for now. |

**`glint.context`**: `appIdentifier`, `appName`, `canPaste`, `canCut`, `canCopy`, `hasFormatting`,
`browserUrl`, `browserTitle` (currently empty).

**`glint.modifiers`**: `{ shift, control, option, command }` booleans.

**`glint.options`**: option values by identifier (booleans as `true`/`false`).

**Functions**

| Call | Does |
| --- | --- |
| `glint.pasteText(text, {restore: true})` | Paste over the selection; `restore` puts the old clipboard back. |
| `glint.copyText(text)` | Copy to the clipboard. |
| `glint.openUrl(url, {activate: false, app: 'com.apple.Safari'})` | Open a URL. `activate: false` opens it in the background; `app` picks the app by bundle ID. |
| `glint.showText(text, {preview: true})` | Show text in the bar (`preview`: clicking copies it). |
| `glint.showSuccess()` / `glint.showFailure()` | Show ✓ / ✗. |
| `glint.showSettings()` | Open this extension's settings. |
| `glint.pressKey('command b')` | Press a key combo (any [key combo](#key-combos) form, or `pressKey(keyCode, modifierFlags)`). |
| `glint.performCommand('copy')` | `cut`, `copy`, `paste`, `paste-plain` (also `pasteMatchStyle`), `select-all`, `undo`, `redo`. |
| `glint.appear()`, `glint.share()` | Accepted for compatibility; they do nothing. |
| `pasteboard.text` | Read the clipboard text; assigning to it copies. |
| `console.log(...)` (`print`, `console.error`/`warn`/`info`) | Write to the extension console. |

**Utilities**

| Call | Does |
| --- | --- |
| `util.base64Encode(s, {urlSafe: true})` | UTF-8 → Base64 (`urlSafe` uses `-`/`_` and drops padding). |
| `util.base64Decode(s)` | Base64 (standard or URL-safe) → UTF-8 string; `""` if invalid. |
| `util.buildQuery({a: 1, b: 'x y'})` | `a=1&b=x%20y` |
| `util.htmlToMarkdown(html)` | Currently strips tags. |
| `util.htmlToRtf(html)` | Returns the input unchanged. |
| `util.localize(s)` | Returns `s`. |
| `util.sleep(ms)` / `sleep(ms)`, `util.timeoutPromise(ms)`, `setTimeout(fn, ms)` | Timing helpers (sleep is capped at 10 s). |
| `fetch(url, {method, headers, body})` | Network request, resolving to `{status, ok, headers, text(), json()}`. |
| `require('axios')` | A small axios-compatible client: `get`, `post`, `put`, `delete`, `request`, `create({baseURL, headers})`. Resolves to `{status, data, headers}`; rejects with `err.response` on non-2xx. |
| `require('./lib.js')` | Load a CommonJS file from the bundle folder (the `.js` extension is optional). |

```js
// #glint
// name: Shorten
// after: paste-result
// requirements: [url]
const axios = require('axios');
const r = await axios.get('https://is.gd/create.php', { params: { format: 'simple', url: glint.input.text } });
return r.data;
```

### JavaScript modules

A module defines the extension in code. Use a bundle with **`Config.js`**, a `Config.yaml`/`.json` that
names the module file (`module: main.js`; the static config keys are used and the module supplies the
actions), or an inverted snippet with `language: javascript` and `module: true`. Export the config keys and an `actions` array:

```js
// ChangeCase.glintext/Config.js (abridged)
module.exports = {
  identifier: 'com.example.case',
  name: 'Case',
  icon: 'symbol:textformat',
  requirements: ['text'],          // inherited by every action
  after: 'paste-result',           // inherited by every action
  options: [ { identifier: 'keepAcronyms', type: 'boolean', defaultValue: true } ],
  actions: [
    { title: 'UPPERCASE', icon: 'text:AB', code: (input, options, context) => input.text.toUpperCase() },
    { title: 'lowercase', icon: 'text:ab', code: (input) => input.text.toLowerCase() },
  ],
};
```

- Module-level keys read: `name`, `identifier`, `icon`, `description`, `requirements`, `regex`, `after`,
  `apps`/`app`, `excludedApps`, `stayVisible`, `captureHtml`, `restorePasteboard`, `options`.
- Per-action keys: `title`, `icon`, `identifier`, `requirements`, `regex`, `after`, `apps`,
  `excludedApps`, `stayVisible`, `captureHtml`, `restorePasteboard`, `description`, and `code(input, options, context)`. The
  arguments are `glint.input`, `glint.options` and `glint.context`. An action may also be a bare function.
- `exports.action = {...}` (or a function) defines a single action.
- **Dynamic actions**: when `exports.actions` is a *function* `(input, options, context) => [...]`, Glint
  calls it for each selection and shows the actions it returns (each `{title, icon, after, code}`).
- Top-level code runs once when the extension loads (to read its config), and again for each run, so keep
  it free of side effects. While the config is read (including before you agree to install) and while
  dynamic `actions` functions build the bar, code runs sandboxed: no network (`fetch`/`axios` reject), no
  timers, no sleeping, and a short time limit (1 s and 0.5 s). Network calls belong in action code.
- In a `Config.yaml`, `module: main.js` loads that file as the module; its exported `actions` become the
  extension's actions.

---

## Icons

An icon is a string spec. Prefixes may be combined: `square filled symbol:star`.

| Spec | Draws |
| --- | --- |
| `symbol:NAME` (`sf:NAME`) | The SF Symbol `NAME`, e.g. `symbol:text.magnifyingglass`. **Preferred.** It must exist on macOS 14. |
| bare symbol name with a dot, e.g. `star.fill` | Same as `symbol:` when such a symbol exists. |
| `text:Ab` | The text itself, scaled to fit. |
| `square Ab`, `circle Ab` | Text (or a symbol) inside an outlined square / circle. |
| `square filled Ab`, `circle filled Ab` | …inside a filled shape, with the content knocked out. |
| short text or emoji (≤ 4 characters), e.g. `🔍`, `MD` | Drawn as text. Longer text is reduced to initials. |
| `icon.png`, `icon.svg`, `.pdf`, `.tiff`, `.jpg`, `.icns` | An image file in the bundle folder. It's drawn as a template (tinted to match the bar) unless the file name contains `color`. |
| `iconify:mdi:home` | An Iconify icon, downloaded once and cached. |

Accepted but ignored for now: the `monospaced`, `strike`, `flip-x`, `flip-y`, `search` and `shape=…`
prefixes. When an action has no icon, its title's initials are used.

---

## Installing, identifiers and debugging

- **Install a snippet**: select its text in any app and click **Install Extension**. It's saved as
  `~/Library/Application Support/Glint/Extensions/<identifier>.glintext/Snippet.txt`.
- **Install a bundle**: open a `.glintext` or `.popclipext` folder with Glint (double-click or drop it on
  the app). It's copied into the same Extensions folder.
- **Develop in place**: edit files in `~/Library/Application Support/Glint/Extensions` and reload
  extensions with **Reload Extensions** in Settings → Actions.
- **Identifiers**: give every extension an `identifier`. Without one, a snippet gets `snippet.<name-slug>`,
  a bundle `bundle.<folder-name>`, and a bundled file `builtin.<file-name>`. A user extension with the same
  identifier as a bundled one replaces it.
- **Console**: script stderr, `console.log` output and failure messages appear in the extension log window.
- **Errors**: extensions that fail to load are listed in Settings → Actions with the reason (missing `name`, no
  action, invalid YAML…).

### A complete bundle example

```
WordTools.glintext/
├── Config.yaml
├── count.sh
└── icon.svg
```

```yaml
name: Word Tools
identifier: com.example.word-tools
description: Count words or look one up.
icon: icon.svg
options:
  - identifier: lang
    label: Wiktionary language
    type: multiple
    values: [en, fr, de]
    value labels: [English, French, German]
actions:
  - title: Count Words
    icon: symbol:number
    shell script file: count.sh
    after: show-result
  - title: Define
    icon: symbol:book
    requirements: [text, '!url']
    regex: '^\s*\S+\s*$'           # single words only
    url: 'https://{glint option lang}.wiktionary.org/wiki/***'
```

```sh
#!/bin/sh
wc -w | tr -d ' '
```

---

## Compatibility notes

Glint is an independent project and is not affiliated with PopClip. For interoperability it also accepts
the PopClip extension format: `#popclip` headers, `.popclipext` folders, PopClip config key names (which
the key normalisation covers), `{popclip …}` placeholders, `POPCLIP_*` environment variables and the
`popclip.*` JavaScript API. Behaviour follows Glint's engine as documented here, so a few details may
differ from other apps.
