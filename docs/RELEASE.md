# Releasing MacControl

MacControl is distributed as a signed DMG (GitHub Releases; notarization is optional and needs a paid account). The Mac App Store is not possible:
the App Sandbox forbids reading SMC sensors and cleaning user folders.

## Three ways to package a release

| Command | Signature | Notarized | First launch on another Mac | Administrator helper |
|---------|-----------|-----------|-----------------------------|----------------------|
| `DEVELOPER_ID="…" NOTARY_PROFILE="…" ./release.sh` | Developer ID | yes | opens without warnings | works |
| `SIGN_IDENTITY="Apple Development" ./release.sh --dev-signed` | free Apple Development cert | no | user confirms once (right-click ▸ Open) | works (pinned to the Team ID) |
| `./release.sh --unsigned` | none | no | user confirms once | unavailable |

The `--dev-signed` mode is what the GitHub releases use. `Scripts/make-dmg.sh` builds the drag-to-install disk image
(with the arrow background; Finder needs a one-time permission for the terminal to arrange the window — without it the
DMG is still created, just plainer).

## Publishing on GitHub

1. Bump the version in `Resources/Info.plist` (`CFBundleShortVersionString`, `CFBundleVersion`) and `CHANGELOG.md`.
2. `./build.sh test`, then `SIGN_IDENTITY="Apple Development" ./release.sh --dev-signed`.
3. Create a release on GitHub (tag `v<version>`), attach `build/MacControl-<version>.dmg` and the `.sha256` file,
   and copy the changelog entry into the description.
4. The README links to `releases/latest`, so it needs no edit.

## What you need

| Item | Why | Cost |
|------|-----|------|
| Apple Developer Program membership | Developer ID certificate + notarization | $99 / year |
| "Developer ID Application" certificate in the login keychain | signs the app and DMG | included |
| App-specific password for your Apple ID | notarytool credentials | free |
| Xcode (or Command Line Tools) | `codesign`, `notarytool`, `stapler` | free |

For development and personal use none of this is needed: `./build.sh` produces an ad-hoc signed app.

## One-time setup

```bash
xcrun notarytool store-credentials "maccontrol-notary" \
    --apple-id "you@example.com" --team-id TEAMID --password "<app-specific password>"
security find-identity -v -p codesigning     # copy the "Developer ID Application: …" name
```

## Each release

1. Bump `CFBundleShortVersionString` / `CFBundleVersion` in `Resources/Info.plist`.
2. Run the unit tests on a machine with Xcode: `./build.sh test`.
3. Build, sign, notarize, staple and package:

```bash
DEVELOPER_ID="Developer ID Application: Your Name (TEAMID)" NOTARY_PROFILE="maccontrol-notary" ./release.sh
```

4. Result: `build/MacControl-<version>.dmg` and its `.sha256`. Upload both to `website/downloads/`
   (the page links to `downloads/MacControl-0.1.0.dmg` — update the file name and version in `website/index.html`).
5. Smoke-test on a clean Mac (download via browser so the quarantine flag is set, open the DMG, launch).

`./release.sh --unsigned` builds the DMG without signing, to check packaging only.

## Before the first public release

- Test on several Intel models (the sensor tables differ). Ask testers to send the output of
  `build/bin/MacControlProbe --stats --all-keys`.
- Walk through every permission prompt (Full Disk Access, Automation, Notifications) on a clean user account.
- Decide whether the privileged helper (SMAppService + XPC) is needed for the first release; without it,
  system-wide files, Time Machine snapshots and other users' processes stay read-only.
- Review the website text and add a privacy statement and contact address.
