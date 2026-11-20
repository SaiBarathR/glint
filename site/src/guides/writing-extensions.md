---
title: Writing extensions
description: Build three small Glint extensions step by step, a web search, a shell transform and a JavaScript action with settings, then package and share them.
---

# Writing extensions

An extension adds one or more buttons to Glint's bar. This guide builds three small ones, each a little more involved
than the last:

1. **MDN**, a web search, in four lines of YAML.
2. **Indent**, a shell script that changes the selected text, which then becomes a folder with its own script file.
3. **Truncate**, a JavaScript action with settings the user can change.

You need Glint installed with Accessibility access, and any text editor. Everything here is covered in more depth in
the [extension reference](/glint/docs/reference/).

## How extensions are installed

The quickest way is a **snippet**: text whose first line is `#glint`, followed by the extension's config. Select a
snippet in any app (including the code blocks on this page) and Glint's bar shows **Install Extension**. Glint shows
what the extension is and which kinds of actions it has, and adds it when you click **Install**. Nothing in it runs
before that.

Installed extensions live in `~/Library/Application Support/Glint/Extensions`, one folder each. Reinstalling a snippet
with the same `identifier` replaces the old version, so you can edit and reinstall as often as you like.

## 1. A web search

Here is a complete extension that searches MDN for the selected text:

```yaml
#glint
name: MDN
identifier: com.example.mdn
icon: symbol:book
url: https://developer.mozilla.org/en-US/search?q=***
```

Select those five lines and click **Install Extension**. Then select a word like `flatMap` anywhere and click the new
book button.

- `name` is the extension's name and the button's tooltip.
- `identifier` keeps your extension apart from others. Use reverse-DNS form with a domain you own, or something
  unlikely to clash.
- `icon` is an [SF Symbol](https://developer.apple.com/sf-symbols/) name after `symbol:`. Short text works too:
  `icon: text:MDN`.
- `url` is opened with `***` replaced by the selection, percent-encoded.

Glint already knows what to do with modifier keys on URL actions: hold <kbd>⇧</kbd> to copy the URL instead of opening
it, or <kbd>⌘</kbd> to open it in the background.

### Make it smarter

Two more keys make this extension nicer to live with:

```yaml
#glint
name: MDN
identifier: com.example.mdn
icon: symbol:book
requirements: [text, '!url']
url: https://developer.mozilla.org/en-US/search?q=***
alternate url: https://caniuse.com/?search=***
```

- `requirements` decides when the button is offered. `text` (the default) means "there is selected text", and `'!url'`
  means "and it isn't a link", so the button stays off the bar when you select a URL. (Quote anything starting with
  `!` in YAML.)
- `alternate url` is used while <kbd>⌥</kbd> is held, here to look the feature up on Can I Use.

Install it again: the same identifier means it replaces the first version.

## 2. A shell transform

Shell scripts are the most flexible kind of action: they can use any command-line tool on your Mac. This one indents
the selected lines by two spaces:

```sh
# #glint
# name: Indent
# identifier: com.example.indent
# icon: symbol:increase.indent
# after: paste-result
sed 's/^/  /'
```

This is an **inverted snippet**: the code comes after a header of comment lines that hold the config. Glint guesses the
language from the comment style (`#` means shell), runs the script with the selection on **stdin**, and takes
**stdout** as the result.

`after: paste-result` puts the result in place of the selection. When the text isn't editable, or when you hold
<kbd>⇧</kbd>, Glint copies the result instead. Without an `after` key, the script would run for its side effects only.

### Read the modifier keys

Let's make <kbd>⌥</kbd> outdent instead. Glint passes the held modifiers to scripts in `GLINT_MODIFIER_FLAGS`, a number
in which Option is `524288`:

```sh
# #glint
# name: Indent
# identifier: com.example.indent
# description: Indent lines by two spaces. ⌥ outdents.
# icon: symbol:increase.indent
# after: paste-result
# trim: false
if [ $(( GLINT_MODIFIER_FLAGS & 524288 )) -ne 0 ]; then
  sed -E 's/^ {1,2}//'
else
  sed 's/^/  /'
fi
```

`trim: false` keeps the selection exactly as it is. By default Glint trims whitespace from both ends of the
selection, which would eat the first line's indentation.

Other environment variables include `GLINT_TEXT` (the selection), `GLINT_APP_NAME` and `GLINT_BUNDLE_IDENTIFIER` (the
app it came from) and `GLINT_OPTION_<NAME>` for each setting. The reference has
[the full list](/glint/docs/reference/#shell-scripts). Scripts run with Homebrew's folders on `PATH`, in the
extension's folder, and are stopped after 30 seconds.

### Turn it into a folder

Longer scripts are easier to edit in their own file. A folder named `Something.glintext` holding a `Config.yaml` and
any scripts is an extension too:

```text
Indent.glintext/
├── Config.yaml
└── indent.sh
```

```yaml
# Indent.glintext/Config.yaml
name: Indent
identifier: com.example.indent
description: Indent lines by two spaces. ⌥ outdents.
icon: symbol:increase.indent
after: paste-result
trim: false
shell script file: indent.sh
```

```sh
#!/bin/sh
# Indent.glintext/indent.sh: the selection arrives on stdin.
if [ $(( GLINT_MODIFIER_FLAGS & 524288 )) -ne 0 ]; then
  sed -E 's/^ {1,2}//'
else
  sed 's/^/  /'
fi
```

Double-click the folder (or drop it on Glint's Settings window) to install it. A folder can hold several actions under
`actions:`, scripts in any language (start them with a `#!` line, or set `interpreter: python3`), images for icons, and
JavaScript files.

While you work on an extension, edit it right in `~/Library/Application Support/Glint/Extensions` and choose
**Reload Extensions** from the **+** menu in Settings → Actions.

## 3. JavaScript with settings

JavaScript actions run inside Glint, in a fresh JavaScriptCore context each time, so they start instantly and don't need
anything installed. This one shortens the selection to a length the user picks:

```yaml
#glint
name: Truncate
identifier: com.example.truncate
description: Shorten the selection to a set length, ending with an ellipsis.
icon: symbol:scissors
after: paste-result
options:
  - identifier: length
    label: Maximum length
    type: multiple
    values: ['80', '140', '280']
    value labels: [80 characters, 140 characters, 280 characters]
    default value: '140'
  - identifier: words
    label: Break between words
    type: boolean
    default value: true
  - identifier: ellipsis
    label: Ending
    type: string
    default value: …
javascript: |
  const max = Number(glint.options.length);
  const ending = glint.options.ellipsis;
  const text = glint.input.text;
  if (text.length <= max) return text;
  let cut = text.slice(0, max - ending.length);
  if (glint.options.words && cut.includes(' ')) {
    cut = cut.slice(0, cut.lastIndexOf(' '));
  }
  return cut.trimEnd() + ending;
```

Install it, then look at it in **Settings → Actions → Truncate**: each entry in `options` is a setting there, with a
picker, a checkbox and a text field.

- The script reads settings from `glint.options`. Booleans are real `true`/`false` in JavaScript (shell scripts get
  `"1"`/`"0"`).
- `glint.input.text` is the selected text. `glint.modifiers.option` and friends tell you which keys were held.
- `return` at the top level is fine: Glint wraps the script in a function when needed, an `async` one if it uses
  `await`.
- Whatever you return is the result. Returning nothing means "no result".

### When something goes wrong

Throw an error to fail: Glint shows ✗ on the bar and writes the message to the **Extension Log** (in the menu bar
menu), along with anything you `console.log`.

```js
if (!Number.isFinite(max) || max < 2) {
  throw new Error('Pick a maximum length in Truncate\'s settings');
}
```

To send the user to the extension's settings instead, call `glint.showSettings()` (a shell script does the same by
exiting with status 2).

### Bigger JavaScript extensions

For more than a few lines, put the code in a folder with a `Config.js` that exports the whole extension. Each action has
a `code(input, options, context)` function:

```js
// Truncate.glintext/Config.js
module.exports = {
  name: 'Truncate',
  identifier: 'com.example.truncate',
  icon: 'symbol:scissors',
  after: 'paste-result',
  actions: [
    { title: 'Truncate to 80', code: (input) => shorten(input.text, 80) },
    { title: 'Truncate to 280', code: (input) => shorten(input.text, 280) },
  ],
};

function shorten(text, max) {
  return text.length <= max ? text : text.slice(0, max - 1).trimEnd() + '…';
}
```

`require('./helpers.js')` loads other files from the folder, and `fetch` or `require('axios')` make network requests
from action code. See [JavaScript](/glint/docs/reference/#javascript) in the reference.

## Share your extension

- **A snippet** can be pasted anywhere: an email, a gist, a chat. Whoever selects it gets **Install Extension**.
- **An install link** opens Glint directly. It's `glint://install?snippet=` followed by the snippet, URL-encoded (in
  JavaScript, `encodeURIComponent(snippet)`). Glint still asks before installing.
- **A folder** can be zipped and renamed to `.glintextz`, which Glint installs on double-click:

  ```sh
  ditto -c -k --keepParent Indent.glintext Indent.glintextz
  ```

The [extensions gallery](/glint/extensions/) has twenty more examples, each with its source.

## Where to go next

- The [extension reference](/glint/docs/reference/) covers every config key, action kind, placeholder, environment
  variable and JavaScript call.
- [Safety and limits](/glint/docs/safety-and-limits/) explains what Glint checks before an extension runs, and the size
  and time limits.
- The extensions that ship with Glint, in
  [App/Resources/Extensions](https://github.com/SaiBarathR/glint/tree/main/App/Resources/Extensions), are working
  examples of every format.
