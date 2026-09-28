# Pad

Pad is a native macOS app for editing individual text and Markdown files. It has no note library, CLI, updater, or integration with another app.

## Working conventions

- American English in repository content. Short, scoped Conventional Commits.
- Feature branches and pull requests. Required CI must pass before squash merging; delete merged branches.
- Preserve unrelated changes and supplied artwork. No compatibility aliases, legacy code, or preference migrations.
- Keep credentials, signing identities, personal paths, and machine details out of the repository. Local signing is rendered into ignored configuration.
- Delegate independent work with explicit file ownership. Serialize GUI verification on an isolated test machine; never launch previews or run tests on an actively used workstation.

## Architecture

- `App/Document/` owns document state, persistence, naming and the native editor panel. `App/Editor/` owns focus helpers.
- The app delegate owns lifecycle; Settings and menus call the same document operations. Keep file operations independent of UI presentation for testing.
- `project.yml` is the identity and build configuration source. The generated Xcode project and shared scheme are committed for Xcode Cloud; regenerate and verify together.
- Release uses Pad and its standard icon. Debug uses Pad Dev, a separate identity, preferences and shortcut, the DEV icon and a visible badge. Test hosts use disposable storage and disable global shortcuts.

## Build and verification

Requires Xcode 27, macOS 27 and XcodeGen. See `README.md` and `RELEASING.md` for current commands.

- Generate with `xcodegen generate`; CI checks the generated project matches the source.
- Build/test through the shared Pad scheme. Run window tests only in an isolated GUI session with `PAD_WINDOW_TESTS` passed to the test host.
- Exercise changed behavior, especially focus, file dialogs, close/discard, naming collisions and external edits. Unit tests do not prove window behavior.
- Do not replace or quit a running development preview without checking whether it is in use. Never test against personal documents.
- Public PRs use hosted CI only; never attach personal persistent runners.

## Delivery

App Store/TestFlight distribution only. Start at 1.0.0; subsequent releases increment the patch version unless explicitly agreed otherwise. Use monotonic build numbers and version-matching tags. An upload is not completion: verify processing, internal tester availability and installation. Xcode Cloud workflow setup is separate from repository preparation.
