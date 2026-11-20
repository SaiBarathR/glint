# Extension gallery

Extensions shown in the gallery on [the website](https://saibarathr.github.io/glint/extensions/). Each is either a
snippet file (`*.txt`, installable from a `glint://install` link or by selecting its text) or a `.glintext` folder.

- `catalog.json` lists every item with its category and examples. The website shows the examples on each card, and
  `Packages/GlintCore/Tests/GlintCoreTests/GalleryExtensionsTests.swift` runs them through the real engine, so a card
  can't show a result the extension doesn't produce.
- Identifiers use the `io.github.saibarathr.glint.gallery.` prefix, so they never replace a bundled extension.
- Everything runs offline except the web searches in Developer Docs.

To add one: put the file or folder here, add an entry to `catalog.json`, and run
`swift test --package-path Packages/GlintCore --filter GalleryExtensionsTests`.
