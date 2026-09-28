# Releasing

Pad starts at 1.0.0. Subsequent releases increment the patch version unless a format or installation change has been agreed. `project.yml` owns product identity, icons, version, and build configuration. Regenerate and commit the Xcode project, shared scheme, generated plist, and entitlements whenever it changes.

## Verification

Use a dedicated development Mac running macOS 27 and Xcode 27 for builds and interactive checks. Never replace or quit an installed app to test a development build. `scripts/build_and_run.sh` builds the isolated Debug product and refuses to replace it while running; `--build-only` skips opening it.

Pull requests use GitHub-hosted `xcode-27` runners, never persistent personal runners. GitHub's [image announcement](https://github.com/actions/runner-images/issues/14404) confirms its macOS 27 base. CI checks generated-project consistency, Debug tests, and a Release build. Window suites use `PAD_WINDOW_TESTS=1`; with xcodebuild, pass `TEST_RUNNER_PAD_WINDOW_TESTS=1`. Leave it unset on an occupied desktop. CI runs `FilenameInputTests` and `PanelTests` in separate, sequential xcodebuild invocations, excluding them from the main run: Swift Testing can otherwise interleave separate serialized suites that compete for the key window. Use the same suite filters for remote interactive verification.

## First internal TestFlight build

1. Merge a reviewed PR after CI passes. Set the version and initial build number in `project.yml`, regenerate, and commit. Verify the actual files, keyboard shortcuts, focus restoration, settings, sharing, external edits, and development/release isolation on the dedicated Mac.
2. Register the distribution bundle identifier from `project.yml` in the developer account. Create a macOS App Store Connect record with the same identifier, name, primary language, and a stable SKU. Complete required compliance and beta metadata and create an internal testing group.
3. Supply `APPLE_DEVELOPMENT_TEAM` through the existing credential manager and run `scripts/render-local-signing.sh`. It writes ignored `Config/Local.xcconfig`; never hand-edit or commit it. Regenerate the project. If the dedicated machine needs signing identities, inject the `PAD_DEVELOPMENT_PRIVATE_KEY`, `PAD_APPLICATION_PRIVATE_KEY`, `PAD_INSTALLER_PRIVATE_KEY`, matching base64 DER `PAD_*_CERTIFICATE` values and `PAD_KEYCHAIN_PASSWORD` from the credential manager, then run `python3 scripts/render-signing-identities.py`. This renders an ignored private keychain and preserves existing keychain search entries.
4. Archive the Release scheme on the dedicated Mac with automatic signing and an explicitly unused build number. Use Xcode Organizer to validate and upload through the intended developer account. Never commit signing identities, profiles, export credentials, or account-specific export options.
5. Wait for App Store Connect processing, resolve any compliance questions, and add the processed build to the internal group. Install it using TestFlight on the dedicated Mac and repeat the release smoke check. Record the build, processing status, group assignment, and installation evidence privately.

An uploaded archive is not completion. The build must be installable by the internal tester. App Store publication and external beta review are separate milestones.

## Xcode Cloud handoff

The owner creates the workflow in Xcode/App Store Connect. Select the committed shared Pad scheme, Release archive action, macOS 27/Xcode 27 toolchain, a tag start condition matching `v*`, and internal TestFlight distribution to the agreed group. Configure Cloud's next build number above every manually uploaded build before the first run; afterward Cloud owns the distribution counter. Do not reset the sequence or reuse a previous build number.

`ci_scripts/ci_post_clone.sh` validates tagged builds against `MARKETING_VERSION` and uses `agvtool` to set `CURRENT_PROJECT_VERSION` from `CI_BUILD_NUMBER` in the build checkout. It enables Cloud-managed automatic signing through ignored `Config/Cloud.xcconfig`. The committed project requires no XcodeGen installation in Cloud.

For each release, update the patch version, regenerate and commit the project, merge a green PR, validate `scripts/validate-release.sh vX.Y.Z`, then push that tag. Confirm Cloud archives, processing succeeds, the internal group receives the build, and installation works. A pushed tag alone is not a shipped build.

Do not configure Sparkle, notarized direct downloads, a CLI, or a second update pipeline for the initial release.
