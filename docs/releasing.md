# Releasing

Pushing a tag such as `v0.2.0` runs `.github/workflows/release.yml`, which:

1. archives the Mac app, signed with Xcode cloud signing,
2. exports a Developer ID build, notarizes it and publishes a DMG on the GitHub release,
3. uploads the same archive to App Store Connect when `APP_STORE_UPLOAD` is `true`.

## One-time setup

In App Store Connect → Users and Access → Integrations, create a team API key with the **Admin** role
(cloud-managed Developer ID signing needs it). Then, in the GitHub repository settings:

| Kind | Name | Value |
|------|------|-------|
| Secret | `ASC_KEY_ID` | The key ID |
| Secret | `ASC_ISSUER_ID` | The issuer ID |
| Secret | `ASC_KEY_P8` | The `.p8` file, base64-encoded: `base64 -i AuthKey_XXXX.p8 \| pbcopy` |
| Variable | `APPLE_TEAM_ID` | The Apple developer team ID |
| Variable | `APP_STORE_UPLOAD` | `true` to also upload to App Store Connect |

For the App Store upload, the app record must exist in App Store Connect with the bundle ID
`io.github.fujiimport.FujiImport` (or change `PRODUCT_BUNDLE_IDENTIFIER` in `project.yml`).

## App Store notes

- The app is sandboxed; every feature has to work inside the sandbox.
- `App/PrivacyInfo.xcprivacy` declares the required-reason APIs (UserDefaults only). No data is collected.
- Review needs a way to test without a camera: point reviewers at the vcam emulator, or provide a demo video.
