# Releasing

Release with `scripts/release.py 0.2.2` from an up-to-date, clean `main`. It runs CI on macOS, Windows and Linux
for that commit unless a manual CI run already passed there (pull requests only run the Linux jobs), sets the
version everywhere, tags it, starts the release build on the tag and waits for it, checks its downloads, then
updates the site (and deploys it with `.github/workflows/site.yml`, which also only runs by hand), the Homebrew
formula and cask and the tap, and lists what's left to do by hand (App Store review,
Microsoft Store). If it stops after tagging, rerun it with `--after` to do the rest. CI runs
`scripts/release.py --check`, which fails when the files name different versions.

`.github/workflows/release.yml` only runs by hand (the script starts it on the tag), and:

1. creates the GitHub release,
2. archives the Mac app, signed with Xcode cloud signing,
3. exports a Developer ID build, notarizes it and attaches a DMG to the release (skipped while
   `DEVELOPER_ID_P12` isn't set),
4. uploads the same archive to App Store Connect when `APP_STORE_UPLOAD` is `true`,
5. builds the Windows (MSI, setup .exe) and Linux (AppImage, .deb, signed when `LINUX_GPG_KEY` is set)
   installers and attaches them.

A new file that names the version goes in `VERSION_FILES` or `PACKAGE_FILES` in `scripts/release.py`, and a new
platform's download in `ASSETS`.

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

- `scripts/app-store.py` does the App Store Connect chores over the API: the review contact, screenshots taken
  against the camera emulator, the Developer ID certificate, uploading a build and submitting it. `status` shows
  what's missing. Only App Privacy has no API.

- The app is sandboxed; every feature has to work inside the sandbox.
- `App/PrivacyInfo.xcprivacy` declares the required-reason APIs (UserDefaults only). No data is collected.
- Review needs a way to test without a camera: point reviewers at the vcam emulator, or provide a demo video.
