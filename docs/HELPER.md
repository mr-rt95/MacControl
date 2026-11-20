# The administrator helper

Some actions need root: system-wide leftovers in `/Library`, deleting Time Machine snapshots, switching system
launch daemons, quitting other users' (and root's) processes, listing root processes (e.g. `kernel_task`) and reading
CPU frequency via `powermetrics`. They are done by a small launchd daemon, `MacControlHelper`.

## Design

- **Whitelist, not a shell.** The helper exposes seven fixed operations (`MacControlHelperProtocol`). It never runs
  arbitrary commands or paths, and re-validates each request itself (`PrivilegedPolicy`) — it does not trust the app.
- **Who may connect.** Only a client signed by the same signer, as a code-signing requirement: either
  `anchor apple generic and identifier "com.maccontrol.app" and certificate leaf[subject.OU] = "<TEAM>"` (Apple-issued
  certificate) or `identifier "com.maccontrol.app" and certificate leaf = H"<SHA-1>"` (self-signed, pinned to that
  exact certificate). The app checks the helper the same way. The signer is baked into both (`MCSigningTeamID` /
  `MCSigningCertHash` in Info.plist; the helper embeds its plist in the executable). A build with neither (ad-hoc
  signed) makes the helper **refuse every connection** — there is deliberately no "trust everyone" mode.
- **Reversible where possible.** System leftovers are *moved* into a root-owned quarantine
  (`/Library/Application Support/MacControl/Quarantine`, kept 30 days) and can be restored with Undo. Launch daemons are
  disabled, not deleted. Snapshot deletion is permanent (the preview says so).
- **Protected items stay protected.** Same rules as the app: `kernel_task`, `launchd`, `WindowServer`, `/System`,
  Apple labels and bundle ids, symlinks leading out of `/Library`, nested paths, the `/Library` roots themselves.
- **Nothing runs unless the user installs it.** Registration goes through `SMAppService.daemon`; macOS asks the user to
  approve it in System Settings ▸ Login Items. It can be removed from the Permissions screen at any time.

## Requirements

- macOS 13 or newer (`SMAppService` daemons, `NSXPCConnection.setCodeSigningRequirement`). On macOS 12 the helper is
  unavailable and the app works without it.
- A code-signing certificate. Three options, none of which requires Xcode:

| Certificate | Trust is pinned to | Cost | How |
|-------------|--------------------|------|-----|
| **Self-signed** (personal use) | the certificate's SHA-1 hash | free | see below |
| Apple Development | your Team ID | free, but only Xcode can create it | Xcode ▸ Settings ▸ Accounts |
| Developer ID (distribution, notarization) | your Team ID | $99 / year | developer.apple.com |

## Self-signed certificate (no Apple account, no Xcode)

Quickest: `Scripts/make-local-certificate.sh` does steps 1–3 below for you (macOS asks for your password once).
By hand:

1. Open **Keychain Access** ▸ menu *Keychain Access* ▸ *Certificate Assistant* ▸ **Create a Certificate…**
2. Name: `MacControl Local` · Identity Type: **Self Signed Root** · Certificate Type: **Code Signing** ·
   keep "Let me override defaults" off ▸ Create.
3. Find it under *My Certificates* (login keychain), double-click ▸ expand **Trust** ▸ set *Code Signing* to
   **Always Trust** (asks for your password). Without this step macOS lists the identity as invalid and
   `codesign` refuses it ("The specified item could not be found in the keychain").
4. Check: `security find-identity -v -p codesigning` shows `"MacControl Local"`.
5. Build: `SIGN_IDENTITY="MacControl Local" ./build.sh run`

`build.sh` reads the certificate's SHA-1 hash and embeds it in the app and the helper. The helper then accepts only a
client whose code signature has `identifier "com.maccontrol.app"` **and** exactly that certificate; the app
checks the helper the same way. Keep the certificate's private key private: whoever has it can talk to the helper.
If you re-create the certificate, rebuild the app (the hash changes) and reinstall the helper.

**Not verified:** whether macOS accepts `SMAppService` registration of a daemon signed by a self-signed certificate.
Apple documents Developer ID / Apple Development signing; self-signed is expected to work for local use but I could not
confirm it on a real machine. If "Install helper" fails with a self-signed build, use an Apple Development certificate.

## Building with the helper

```bash
security find-identity -v -p codesigning        # find the certificate name
SIGN_IDENTITY="Apple Development" ./build.sh install    # or a full name / "MacControl Local"
```

`install` puts the app in `/Applications` and removes the copy in `build/`: macOS registers the helper from one
location, and two copies with the same identifier make it pick the wrong one (the helper then breaks as soon as
`build/` is cleaned). If you ever move the app, use *Remove helper* → *Install helper* again.

Apple Development certificates need Apple's intermediate certificate (WWDR G3) in your keychain. If `codesign` says
"unable to build chain to self-signed root", download it from apple.com/certificateauthority and import it.

Then open **Permissions ▸ Administrator helper ▸ Install helper**, approve MacControl in System Settings ▸ General ▸
Login Items & Extensions, and return to the app. The card changes to "Active" once the helper answers.

Without `SIGN_IDENTITY` the app is ad-hoc signed and the card reads "Unavailable in this build".

## What is verified, and what is not

Verified by automated checks (no root needed): every validation rule, the operations on a temporary `/Library`
(quarantine, restore, tampered manifests, launchctl/tmutil arguments), and a real XPC round trip against an in-process
listener (`Tests/MacControlCoreTests/HelperTests.swift`).

**Not verified on a real installation** (needs a certificate and an interactive approval): `SMAppService` registration,
the code-signing requirement matching between the real app and the real daemon, `launchctl` against real system
daemons, `tmutil deletelocalsnapshots`, and the `powermetrics` output format on Intel Macs. Test these on a signed build
before relying on them, and report the `powermetrics` output if the "Extended CPU data" card looks wrong.
