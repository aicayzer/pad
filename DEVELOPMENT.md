# Development

PadPad is a native SwiftUI/AppKit app with an offline Markdown editor. Read [AGENTS.md](AGENTS.md) for architecture and contribution conventions, and [RELEASING.md](RELEASING.md) for distribution.

## Requirements

- macOS 27 and Xcode 27
- XcodeGen
- Node.js and pnpm

## Build

The committed Xcode project is generated from `project.yml`. After changing project configuration, regenerate it with:

```sh
xcodegen generate
```

Open `Pad.xcodeproj` and select the shared **Pad** scheme. Debug builds use **PadPad Dev**, with separate preferences and identity. The app build installs and bundles the Markdown editor through its build script.

Signing configuration is local and ignored. Do not commit credentials, signing identities, or personal paths.

## Verification

Run editor checks in `editor/`:

```sh
pnpm install --frozen-lockfile
pnpm typecheck
pnpm test
pnpm build
```

Use the shared Pad scheme for native build and tests. Window tests require an isolated GUI session and `PAD_WINDOW_TESTS` in the test host environment. Use disposable files, never personal documents. Required CI must pass before merging a pull request; native interaction checks are also needed for changes to focus, save, rename, close, or window behavior.

Public pull requests use hosted CI. Do not attach personal persistent runners.
