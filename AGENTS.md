# PadPad

PadPad is a native macOS app for editing individual text and Markdown files. It has no note library, CLI, updater, or integration with another app.

## Product behavior

- Initial application launch stays hidden, including login launch. A global shortcut, menu command, explicit reopen or file-open event presents the editor. Saved Dock/menu-bar access must remain effective after launch and activation.
- The Aa control beside Share reveals Markdown formatting controls, hidden initially each session. Formatting shortcuts continue to work while controls are hidden. Use neutral adaptive foreground colors for formatting, not the chosen accent.
- Scratch text is intentionally temporary, including clipboard cleanup. With automatic saving off, closing hides the scratch pad; reopening within its configured time away restores the text. Reopening after expiry starts empty, without a recovery archive or discard prompt. Start the interval on dismissal and restart it after every reopen/dismiss cycle. Never expire active text or treat Settings and owned dialogs as dismissal. Do not discard scratch text immediately on close or focus loss. Scratch stays in memory only; app termination does not preserve it.
- Automatic saving and explicit Save preserve work as files. Scratch expiry must never delete saved files or silently discard edits to an opened file.
- Markdown editing displays editable formatted content without automatic source-mode fallback. Preserve unsupported constructs as literal content and retain the exact source until edited. Plain text remains a separate supported format; no RTF or image management.
- Obtain a current, document-scoped editor snapshot before saving, sharing, replacing, closing or quitting. Snapshot and save failures retain the document and show an error.
- Onboarding and discarded-draft recovery are deferred; do not add an archive or retention mechanism implicitly.

## Working conventions

- American English in repository content. Short, scoped Conventional Commits.
- Feature branches and pull requests. Required CI must pass before squash merging; delete merged branches.
- Preserve unrelated changes and supplied artwork. No compatibility aliases, legacy code, or preference migrations.
- Keep credentials, signing identities, personal paths, and machine details out of the repository. Local signing is rendered into ignored configuration.
- Delegate independent work with explicit file ownership. Serialize GUI verification on an isolated test machine; never launch previews or run tests on an actively used workstation.

## Architecture

- `App/Document/` owns document state, persistence, naming and the native editor panel. `App/Editor/` owns the offline Markdown bridge and focus helpers. `editor/` owns the independently copied Milkdown/ProseMirror editor and its single-file bundle; it has no cross-repository dependency.
- The app delegate owns lifecycle; Settings and menus call the same document operations. Keep file operations independent of UI presentation for testing.
- `project.yml` is the identity and build configuration source. The generated Xcode project and shared scheme are committed for Xcode Cloud; regenerate and verify together.
- Release uses PadPad and its standard icon. Debug uses PadPad Dev, a separate identity, preferences and shortcut, the DEV icon and a visible badge. Test hosts use disposable storage and disable global shortcuts.

## Build and verification

Requires Xcode 27, macOS 27, XcodeGen, Node.js and pnpm. See `README.md` and `RELEASING.md` for current commands.

- In `editor/`, run `pnpm install --frozen-lockfile`, `pnpm typecheck`, `pnpm test` and `pnpm build` on the isolated test machine. The app build bundles the editor offline.
- Generate with `xcodegen generate`; CI checks the generated project matches the source.
- Build/test through the shared Pad scheme. Run window tests only in an isolated GUI session with `PAD_WINDOW_TESTS` passed to the test host.
- Exercise changed behavior, especially focus, file dialogs, close/discard, naming collisions and external edits. Unit tests do not prove window behavior.
- Do not replace or quit a running development preview without checking whether it is in use. Never test against personal documents.
- Public PRs use hosted CI only; never attach personal persistent runners.

## Delivery

App Store/TestFlight distribution only. Start at 1.0.0; subsequent releases increment the patch version unless explicitly agreed otherwise. Use monotonic build numbers and version-matching tags. An upload is not completion: verify processing, internal tester availability and installation. Xcode Cloud workflow setup is separate from repository preparation.
