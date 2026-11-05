# Releasing

Pushing a tag such as `v0.2.0` runs `.github/workflows/release.yml`, which:

1. creates the GitHub release,
2. archives the Mac app, signed with Xcode cloud signing,
3. exports a Developer ID build, notarizes it and attaches a DMG to the release (skipped while
   `DEVELOPER_ID_P12` isn't set),
4. uploads the same archive to App Store Connect when `APP_STORE_UPLOAD` is `true`,
5. builds the Windows (MSI, setup .exe) and Linux (AppImage, .deb, signed when `LINUX_GPG_KEY` is set)
   installers and attaches them.

Before tagging, set the new version in `project.yml` (`MARKETING_VERSION`), `apps/desktop/package.json`,
`apps/desktop/src-tauri/tauri.conf.json`, `apps/desktop/src-tauri/Cargo.toml`, `Sources/ferryctl/main.swift` and
`site/site.json`. After the release, update the version, URL and checksum in `packaging/` (Flathub, Homebrew).

## One-time setup

In App Store Connect → Users and Access → Integrations, create a team API key with the **Admin** role
(for provisioning and uploads). Then, in the GitHub repository settings:

| Kind | Name | Value |
|------|------|-------|
| Secret | `ASC_KEY_ID` | The key ID |
| Secret | `ASC_ISSUER_ID` | The issuer ID |
| Secret | `ASC_KEY_P8` | The `.p8` file, base64-encoded: `base64 -i AuthKey_XXXX.p8 \| pbcopy` |
| Variable | `APPLE_TEAM_ID` | The Apple developer team ID |
| Variable | `APP_STORE_UPLOAD` | `true` to also upload to App Store Connect |
| Secret | `DEVELOPER_ID_P12` | A *Developer ID Application* certificate with its private key, exported from Keychain Access as .p12, base64-encoded |
| Secret | `DEVELOPER_ID_P12_PASSWORD` | The password chosen when exporting the .p12 |

App Store Connect API keys can't use Xcode's cloud-managed Developer ID certificate, so the Developer ID build
needs its own certificate. Only the Account Holder can create one: developer.apple.com → Certificates → **+** →
*Developer ID Application*.

Run the workflow by hand (Actions → Release → Run workflow) for a dry run: it signs both builds, notarizes the
DMG and keeps it as a build artifact, without publishing anything.

For the App Store upload, the app record must exist in App Store Connect with the bundle ID
`io.github.fujiimport.FujiImport` (or change `PRODUCT_BUNDLE_IDENTIFIER` in `project.yml`).

## App Store notes

- The app is sandboxed; every feature has to work inside the sandbox.
- `App/PrivacyInfo.xcprivacy` declares the required-reason APIs (UserDefaults only). No data is collected.
- Review needs a way to test without a camera: point reviewers at the vcam emulator, or provide a demo video.
