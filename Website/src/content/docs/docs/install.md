---
title: Install and run
description: Building Eskele from source, installing it, and what happens on first launch.
---

Eskele is a SwiftPM package that has to be assembled into a real application bundle: SwiftPM alone
produces a bare executable, and the agent behaviour — no Dock tile, no menu of its own — needs a
bundle with an `Info.plist`.

## Build and run

```bash
make run
```

That builds a release binary, assembles `Eskele.app`, signs it, and launches it.

The app has **no Dock tile and no menu bar of its own**. After it starts, look for its icon in the
**system menu bar** — that is where every setting lives.

## Run the tests

```bash
make test
```

## Install it properly

Copy the built bundle into `/Applications` and run it from there:

```bash
cp -R .build/release/Eskele.app /Applications/
```

**Grant permissions to the copy you actually use.** macOS records a permission against a specific
application on disk, so a grant made to the copy in `.build` does not carry over to the one in
`/Applications`. Install first, then grant. See [Permissions](../permissions/).

## Signing

`Scripts/build-app.sh` signs with a Developer ID or Apple Development certificate when it finds one,
and warns if it has to fall back to an ad-hoc signature.

This matters more than it looks. macOS does not remember "this app" for a permission — it remembers a
**code signature**. An ad-hoc signature's identity is a hash of the binary, so **every rebuild looks
like a brand new application** and your grants stop applying, while still appearing ticked in System
Settings.

A real certificate gives a stable identity that survives rebuilding. If you have changed signing
identity — including on the first build after a certificate became available — remove Eskele from
*System Settings ▸ Privacy & Security ▸ Accessibility* and add it back, because the old entry refers
to the old identity.

## Launch at login

*Settings ▸ General ▸ Launch at login.* It registers the bundle with `SMAppService`, so macOS lists
it under *System Settings ▸ General ▸ Login Items* like any other.

## Updates

A copy downloaded from the [releases page](https://github.com/hossainalhaidari/eskele/releases)
keeps itself up to date. *Settings ▸ General ▸ Updates* chooses how:

| Choice | What happens |
|---|---|
| **Install Automatically** | Checks once a day, downloads in the background, installs the next time Eskele quits. If it goes a long time without quitting, it offers to restart instead. |
| **Ask Before Installing** | Checks once a day, then shows what it found, with the release notes, before downloading anything. |
| **Only When I Check** | Never looks on its own. |

It starts on **Only When I Check**, so a fresh copy never goes online until you pick another choice.
**Check Now** beside the version, or **Check for Updates…** in the menu-bar menu, looks straight
away. [Privacy](../privacy/#the-one-time-it-goes-online) lists exactly what a check sends.

Eskele is never the frontmost app on its own, so an update found while you are working does not
open a window behind whatever you are doing. It waits in the menu-bar menu — *Update to Eskele
1.2.0…* — and in the General pane until you choose it. One found just after launch, or once the Mac
has been idle, is shown straight away.

Every update is checked against a key built into your copy before it is installed, and refused if it
does not match. Releases are all signed with the same Developer ID, so permissions you granted keep
working after an update.

**A copy you build yourself does not update itself**, and the General pane says so.

## Releasing a signed, notarised build

Releases come from GitHub Actions, from `main` only: push a tag on a commit on `main`, or run the
*Release* workflow by hand, which tags the current `main`.

```bash
git tag v1.2.0 && git push origin v1.2.0
gh workflow run release.yml -f version=1.2.0
```

It tests, builds, signs with Hardened Runtime, notarises and staples the DMG, writes the appcast that
installed copies read, and publishes the GitHub release with both attached. The build number is the
commit count on `main` — Sparkle decides what is newer by that number, so it only ever goes up. It
refuses a version that is not plain `x.y.z`, a tag on a commit that is not on `main`, a version no
newer than the last release, and an `Info.plist` with no update key.

Installed copies read `releases/latest/download/appcast.xml`, which GitHub redirects to the appcast on
the newest release. Publishing the release *is* publishing the update, and it only works while the
repository is public.

### One-time setup

1. **The update key.** `make update-key` makes the EdDSA key pair Sparkle checks every update
   against, keeps the private half in your login Keychain, and writes the public half into
   `Resources/Info.plist`. Commit that, and keep a copy of the private key somewhere safe: installed
   copies can only be moved off a lost key by a release signed with the same Developer ID.
2. **A `release` environment.** *Settings ▸ Environments ▸ New environment*, named `release`. Under
   *Deployment branches and tags*, choose *Selected branches and tags* and add the branch `main` and
   the tag pattern `v*`, so its secrets are out of reach of every other branch and tag. Adding
   yourself under *Required reviewers* makes every release wait for your approval.
3. **Its secrets**, each set with `gh secret set <NAME> --env release`:

   | Secret | What it holds |
   |---|---|
   | `DEVELOPER_ID_CERTIFICATE` | The *Developer ID Application* certificate with its private key, exported from Keychain Access as a `.p12` and base64-encoded: `base64 -i developer-id.p12 \| gh secret set DEVELOPER_ID_CERTIFICATE --env release` |
   | `DEVELOPER_ID_CERTIFICATE_PASSWORD` | The password the `.p12` was exported with |
   | `NOTARY_API_KEY` | An App Store Connect API key, the whole `AuthKey_….p8` file: `gh secret set NOTARY_API_KEY --env release < AuthKey_….p8`. Made under *Users and Access ▸ Integrations ▸ App Store Connect API*, with the Developer role |
   | `NOTARY_API_KEY_ID` | That key's ID |
   | `NOTARY_API_ISSUER_ID` | The issuer ID shown above the list of keys |
   | `SPARKLE_PRIVATE_KEY` | The update key, exported as `make update-key` shows at the end |

Secrets stay private when the repository is public: GitHub never shows one again once it is set, and
masks them in the logs. Workflows run for pull requests from forks get no secrets at all. A ruleset
on `v*` tags (*Settings ▸ Rules ▸ Rulesets*) that allows only you to create them keeps releases yours
even if you add collaborators.

### By hand

To try the pipeline on your own Mac instead:

```bash
export SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
xcrun notarytool store-credentials EskeleNotary \
  --apple-id you@example.com --team-id TEAMID --password <app-specific-password>
export NOTARY_PROFILE=EskeleNotary
ESKELE_VERSION=1.2.0 ESKELE_BUILD=212 make package
```

Without `ESKELE_VERSION` the DMG holds a development build, which never updates itself. Without
`NOTARY_PROFILE` it stops after signing and says so.

## The app icon

The source is `Resources/AppIcon.icon`, an Icon Composer document — `icon.json` names the background
gradient and the layer stack, and `Assets/` holds one SVG per layer. Edit it in Icon Composer (it
ships inside Xcode) or edit the SVGs by hand, then:

```bash
Scripts/make-icon.sh
```

That emits both products macOS needs, and both are committed so an ordinary `make app` needs no
Xcode:

| Product | Read via | Used by |
|---|---|---|
| `Resources/Assets.car` | `CFBundleIconName` | macOS 26, which renders the layers as Liquid Glass and derives the dark, clear and tinted appearances itself |
| `Resources/AppIcon.icns` | `CFBundleIconFile` | macOS 25 and earlier, which get a flat rendering |
