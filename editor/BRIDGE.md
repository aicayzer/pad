# Editor bridge

The app bundles the editor offline. `window.webkit.messageHandlers.host` receives JSON messages:

- `ready`: the editor and `window.editor` are available.
- `changed`: `markdown` and the integer `generation` supplied to `load` or `reload`.
- `state`: `marks` (`bold`, `italic`, `strikethrough`, `code`, `link`), `block` (`paragraph`, `heading` with `level`, `codeBlock`, `bulletList`, `orderedList`, `taskList`), and `quoted`.
- `requestLink` opens the native link editor for Command-K.
- `openLink` with `href`, `copy` with `text`, and `error` with `message`.

Native calls on `window.editor`:

- `load(markdown, generation)` replaces the document and moves the caret to its end.
- `reload(markdown, generation)` replaces content while retaining the caret and scroll position.
- `markdown()` synchronously reads current content, returning `null` if the document matches its loaded baseline. The host must retain the original source in this case, so merely opening a document never rewrites it.
- `insertText(text, generation)` applies buffered native typing through the editor's input rules and rejects stale documents. The host awaits completion before releasing later typing or taking a snapshot.
- `keyDown(key, code, metaKey, ctrlKey, altKey, shiftKey, generation)` offers buffered commands to existing keymaps and returns whether they handled the event. Unhandled browser and app keys retain native handling.
- `format(command, arg?)`, `focus()`, `find(text)`, `insertPaths(paths, x, y)`, `setAccent(color)`, `setTextSize(px)`, `setKeymap(bindings)`.

Formatting commands are `bold`, `italic`, `strikethrough`, `code`, `heading` (level 1–3), `paragraph`, `codeBlock` (optional language), `quote`, `bulletList`, `orderedList`, `taskList`, and `link` (URL).

The host must snapshot before document operations rather than depending on change notifications, reject stale generations, and retain content if retrieval fails. Loading resets undo history. Formatting key bindings belong to the host.

Common Markdown is formatted regardless of its original spelling. HTML, images, reference syntax, frontmatter, tables and footnotes are retained in editable literal blocks; they are never executed or fetched. The surrounding supported content stays formatted. Edited supported Markdown uses canonical serialization. There is no whole-document source fallback, image storage, or network access.
