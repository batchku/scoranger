# Headless TestFlight deploys

Goal: build, sign and upload from a chat session with nothing to click on the
laptop — no Xcode Organizer, no signed-in Xcode account, no Apple ID prompt.

```sh
ios/scripts/bootstrap_signing.sh      # once, ever
ios/scripts/deploy_testflight.sh      # every release
```

---

## Why the previous attempt fell back to Xcode's account

Build 113 was uploaded with `xcodebuild -exportArchive`, but only after the
App Store Connect key was dropped from the command. With the key it failed:

```
error: exportArchive Cloud signing permission error
error: exportArchive No signing certificate "iOS Distribution" found
```

What the state assessment found:

| Checked | Result |
|---|---|
| Distribution certs in the keychain | **none** — only two `Apple Development` identities |
| Distribution *profile* for the app | present: `iOS Team Store Provisioning Profile: com.irllabs.scoranger`, expires 2026-12-12 |
| Certificate embedded in that profile | `Apple Distribution: IRL Labs LLC (V9DBGV72NL)` |
| API key role | **Admin** — it can read `/v1/users`, which only Admin can |
| Certificates the key can see | 2, both `DEVELOPMENT`. The distribution cert is **invisible to it** |
| Profiles the key can see | **0** |
| Project signing | `CODE_SIGN_STYLE: Automatic`, team `V9DBGV72NL` |

The contradiction — a distribution profile and a valid signed upload, but no
distribution private key anywhere on the Mac — is the signature of **Xcode
cloud signing**. Apple holds the private key and signs server-side. That is
why the upload worked through Xcode's logged-in account and failed through the
API key: cloud-managed signing assets are hidden from API keys unless the
Account Holder explicitly grants that access, and the role alone does not
carry it.

**So the role was never the blocker.** The blocker is the dependency on cloud
signing itself, which is interactive by design.

## The fix: stop using cloud signing

Create an ordinary distribution certificate whose private key lives on this
machine, and sign locally. The API key already has everything needed to do
this (Admin, with Certificates/Identifiers/Profiles access — verified above),
so it needs no new permission and no web UI step.

`bootstrap_signing.sh` does it in one pass:

1. Generates a 2048-bit RSA private key in `~/.scoranger-signing/` and a CSR.
   The private key never leaves the machine; Apple only sees the CSR.
2. `POST /v1/certificates` with `certificateType: IOS_DISTRIBUTION` — Apple
   issues the certificate, and because *we* generated the key pair, the result
   is a normal certificate the key can see and manage, not a cloud-managed one.
3. Imports the certificate and key into a dedicated keychain
   (`scoranger-signing.keychain-db`) with no auto-lock, and runs
   `security set-key-partition-list` so `codesign` never raises a GUI prompt.
   That prompt is the single most common cause of a "headless" build hanging.
4. `POST /v1/profiles` with `profileType: IOS_APP_STORE`, binding the app's
   bundle ID to that certificate, and installs the `.mobileprovision`.

`deploy_testflight.sh` then bumps the build number, archives with manual
signing forced on the command line, exports with `signingStyle: manual`,
uploads with the API key, and waits for the build to register.

## Why not fastlane

`fastlane match` solves a problem this project does not have: sharing one
signing identity across *many* machines, by keeping certificates in a separate
encrypted git repository. That buys portability at the cost of another repo,
another passphrase, and another sync step.

Here there is one Mac. Everything match would provide is already covered by
four API calls and a keychain, with the identity created directly rather than
mirrored through storage. Fewer secrets, fewer moving parts, one less repo to
keep in sync.

`fastlane pilot` was likewise unnecessary: `xcodebuild -exportArchive` with
`destination: upload` already uploads, and takes the same API key.

If a second machine or a hosted CI runner ever enters the picture, that is the
moment to add `match` — the certificate created here can be imported into it.

---

## (a) Steps only Ali can do — in the web UI

**On the happy path, none.** The API key already has Admin access with
Certificates, Identifiers & Profiles permission, which is everything the
bootstrap needs. Ali only needs to approve *running* the bootstrap, because it
creates a certificate in the shared team account.

These are the situations that would need him, with exact locations:

### If the bootstrap fails with a certificate limit error

Apple caps distribution certificates per team (typically 3). One of the
existing ones must be revoked before a new one can be issued.

- <https://developer.apple.com> → **Account** → **Certificates, Identifiers &
  Profiles** → **Certificates** (left sidebar)
- Find the `Apple Distribution` entries for team **IRL Labs LLC (V9DBGV72NL)**
- Revoke one that is unused. **Revoking invalidates every build signed with
  it**, so do not revoke the cloud-managed one that build 113 used unless that
  build is finished with.

### If you would rather keep cloud signing than create a local certificate

This is the alternative to the whole approach above. It needs the Account
Holder, because only the Account Holder can hand an API key access to
cloud-managed certificates.

- App Store Connect → **Users and Access** → **Integrations** tab →
  **App Store Connect API** → **Team Keys**
- The access to grant is *Access to Cloud Managed Distribution Certificate*,
  offered when a key is generated. Apple does not allow a key's role to be
  edited after creation, so this generally means **generating a new key** with
  the **Admin** role and that option enabled, then replacing `ASC_KEY_ID` in
  `ios/.deploy.env` and dropping the new `.p8` into
  `~/.appstoreconnect/private_keys/`.
- I could not verify the exact placement of that control from here, so treat
  the wording as approximate and the location as the right page.

With that granted, `deploy_testflight.sh` works with `signingStyle: automatic`
and `-allowProvisioningUpdates` instead, and `bootstrap_signing.sh` becomes
unnecessary. It is a legitimate choice; it trades one web UI action for a
dependency on Apple's signing service at every build.

### If the API key is ever rotated or revoked

- Same page: App Store Connect → Users and Access → Integrations →
  App Store Connect API
- Generate a key with the **Admin** role, download the `.p8` (Apple allows the
  download **once**), place it at
  `~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8`
- Update `ASC_KEY_ID` in `ios/.deploy.env`. The **Issuer ID** is shown once at
  the top of that same page and is the same for every key on the team.

## (b) What is automated in the repo

| File | Role |
|---|---|
| `scripts/bootstrap_signing.sh` | One-time: certificate, keychain, profile |
| `scripts/deploy_testflight.sh` | Every release: bump, archive, sign, upload, wait |
| `scripts/lib/asc.py` | App Store Connect API client (JWT auth, certs, profiles, build status) |
| `scripts/lib/deploy_common.sh` | Shared config and preflight helpers |
| `scripts/bump_build.sh` | Increments `CURRENT_PROJECT_VERSION` |
| `ExportOptions.plist` | Manual signing, upload destination, no Xcode-managed build numbers |
| `ExportOptions-cloud.plist` | Fallback: automatic (cloud) signing, **not headless** — see below |
| `.deploy.env.example` | The credentials contract (real file is gitignored) |

### Credentials

`ios/.deploy.env`, gitignored, holds only identifiers and a local keychain
password:

```
ASC_KEY_ID=…            # 10-char key id
ASC_ISSUER_ID=…         # team issuer UUID
SIGNING_KEYCHAIN_PASSWORD=…
```

The `.p8` private key stays in `~/.appstoreconnect/private_keys/` and is read
only by `asc.py`. It is never copied into the repo, echoed, or passed on a
command line.

### Checking readiness without building

```sh
ios/scripts/deploy_testflight.sh --preflight              # is a headless deploy possible?
engine/.venv/bin/python ios/scripts/lib/asc.py check      # what can the key see?
engine/.venv/bin/python ios/scripts/lib/asc.py builds     # recent TestFlight builds
```

`--preflight` verifies the tools, the vendored build inputs, the signing
identity, the profile and its expiry, and that the API key authenticates —
and changes nothing.

### Useful flags

```sh
ios/scripts/deploy_testflight.sh --no-bump   # re-upload attempt, same number
ios/scripts/deploy_testflight.sh --no-wait   # don't block on processing
```

## Until the bootstrap has been run

`bootstrap_signing.sh` has not been run yet, so there is still no local
distribution identity and `deploy_testflight.sh` will refuse at preflight.
Releases meanwhile go out the way builds 113 and 114 did — archive with
automatic signing, then:

```sh
xcodebuild -exportArchive \
  -archivePath build/Scoranger.xcarchive \
  -exportOptionsPlist ExportOptions-cloud.plist \
  -exportPath build/export
```

Note the absence of `-authenticationKey*`: passing the API key makes this fail
with "Cloud signing permission error", because cloud signing is tied to the
Mac's signed-in Apple ID rather than to the key. **This path is not headless.**
It needs a logged-in Xcode account on the machine and cannot be driven from a
phone. Running the bootstrap is what retires it.

## Known constraints

- **Build numbers never repeat.** App Store Connect rejects a build whose
  `CFBundleVersion` is not higher than the last one for the same marketing
  version. `deploy_testflight.sh` bumps before archiving; `--no-bump` will be
  rejected if that number was already uploaded.
- **The Mac must be powered on and logged in.** The dedicated keychain is
  unlocked by the script, so a locked *screen* is fine, but a logged-out or
  sleeping machine is not.
- **Processing lag is normal.** Build 113 was accepted immediately but took
  well over 10 minutes to appear in the API. `wait-build` polls for 30 minutes
  and says so rather than failing silently.
