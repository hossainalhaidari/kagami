---
title: Install and run
description: Downloading Kagami, installing it with Homebrew, building it from source, and how it updates.
---

Kagami needs **macOS 14 Sonoma or later** on an **Apple silicon** Mac.

## Download

Get the DMG from the [releases page](https://github.com/hossainalhaidari/kagami/releases), open it,
and drag Kagami to Applications. Every release is signed with a Developer ID and notarised by Apple,
so it opens without a Gatekeeper warning.

## With Homebrew

```bash
brew install --cask hossainalhaidari/tap/kagami
```

That taps [hossainalhaidari/homebrew-tap](https://github.com/hossainalhaidari/homebrew-tap), trusts
the Kagami cask in it — naming it in full is what Homebrew takes as your say-so — and installs the
same signed, notarised DMG as the releases page. The copy keeps itself up to date as below, so
`brew upgrade` leaves it alone; `brew upgrade --greedy` moves it on anyway.
`brew uninstall --zap --cask kagami` removes its settings along with it.

## Build and run

Kagami is a SwiftPM package that is assembled into a real application bundle. It needs Xcode's
command-line tools and nothing else.

```bash
make run    # build a release binary, assemble Kagami.app, sign it, launch it
make test   # run the test suite
```

The tests flash real images — every supported format — onto a throwaway 16 MB RAM disk that they
attach and detach themselves. They never touch a real drive.

`Scripts/build-app.sh` signs with an Apple Development or Developer ID certificate when it finds one,
and falls back to an ad-hoc signature when it does not.

## Updates

A copy downloaded from the [releases page](https://github.com/hossainalhaidari/kagami/releases)
keeps itself up to date. *Kagami ▸ Settings… ▸ Updates* chooses how:

| Choice | What happens |
|---|---|
| **Install Automatically** | Checks once a day, downloads in the background, installs the next time Kagami quits. |
| **Ask Before Installing** | Checks once a day, then shows what it found, with the release notes, before downloading anything. |
| **Only When I Check** | Never looks on its own. |

It starts on **Only When I Check**, so a fresh copy never goes online until you pick another choice.
**Check Now** in Settings, or **Check for Updates…** in the Kagami menu, looks straight away.
[Privacy](../privacy/) lists exactly what a check sends.

An update **never restarts Kagami in the middle of a flash**: if you choose *Install and Relaunch*
while a drive is being written, the restart waits until the flash has finished.

Every update is checked against a key built into your copy before it is installed, and refused if it
does not match. **A copy you build yourself does not update itself**, and Settings says so.

## Releasing a signed, notarised build

Releases come from GitHub Actions, from `main` only: push a tag on a commit on `main`, or run the
*Release* workflow by hand, which tags the current `main`.

```bash
git tag v1.2.0 && git push origin v1.2.0
gh workflow run release.yml -f version=1.2.0
```

It tests, builds, signs with Hardened Runtime, notarises and staples the DMG, writes the appcast that
installed copies read, and publishes the GitHub release with both attached. Then it moves the cask in
`homebrew-tap` to the new version and the published DMG's checksum; if only that part fails, *Re-run
failed jobs* retries it alone. The build number is the commit count on `main` — Sparkle decides what
is newer by that number, so it only ever goes up. It refuses a version that is not plain `x.y.z`, a
tag on a commit that is not on `main`, a version no newer than the last release, a version with no
section in `CHANGELOG.md`, and an `Info.plist` with no update key.

Installed copies read `releases/latest/download/appcast.xml`, which GitHub redirects to the appcast on
the newest release. Publishing the release *is* publishing the update, and it only works while the
repository is public.

### One-time setup

1. **The update key.** `make update-key` makes the EdDSA key pair Sparkle checks every update
   against, keeps the private half in your login Keychain (account `kagami`), and writes the public
   half into `Resources/Info.plist`. Commit that, and keep a copy of the private key somewhere safe:
   installed copies can only be moved off a lost key by a release signed with the same Developer ID.
2. **A `release` environment.** *Settings ▸ Environments ▸ New environment*, named `release`. Under
   *Deployment branches and tags*, choose *Selected branches and tags* and add the branch `main` and
   the tag pattern `v*`, so its secrets are out of reach of every other branch and tag.
3. **Its secrets**, each set with `gh secret set <NAME> --env release`:

   | Secret | What it holds |
   |---|---|
   | `DEVELOPER_ID_CERTIFICATE` | The *Developer ID Application* certificate with its private key, exported from Keychain Access as a `.p12` and base64-encoded: `base64 -i developer-id.p12 \| gh secret set DEVELOPER_ID_CERTIFICATE --env release` |
   | `DEVELOPER_ID_CERTIFICATE_PASSWORD` | The password the `.p12` was exported with |
   | `NOTARY_API_KEY` | An App Store Connect API key, the whole `AuthKey_….p8` file: `gh secret set NOTARY_API_KEY --env release < AuthKey_….p8` |
   | `NOTARY_API_KEY_ID` | That key's ID |
   | `NOTARY_API_ISSUER_ID` | The issuer ID shown above the list of keys |
   | `SPARKLE_PRIVATE_KEY` | The update key, exported as `make update-key` shows at the end |
4. **The tap's deploy key.** A key pair that can push to `homebrew-tap` and nothing else:

   ```bash
   ssh-keygen -t ed25519 -N '' -C 'kagami release' -f tap-key
   gh repo deploy-key add tap-key.pub --repo hossainalhaidari/homebrew-tap --allow-write --title 'kagami release'
   gh api -X PUT repos/hossainalhaidari/kagami/environments/homebrew-tap
   gh secret set HOMEBREW_TAP_DEPLOY_KEY --env homebrew-tap < tap-key
   rm tap-key tap-key.pub
   ```

   Then give the new `homebrew-tap` environment the same *Deployment branches and tags* as `release`.

Secrets stay private when the repository is public: GitHub never shows one again once it is set, and
masks them in the logs. Workflows run for pull requests from forks get no secrets at all.

### By hand

To try the pipeline on your own Mac instead:

```bash
export SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
xcrun notarytool store-credentials KagamiNotary \
  --apple-id you@example.com --team-id TEAMID --password <app-specific-password>
export NOTARY_PROFILE=KagamiNotary
KAGAMI_VERSION=1.2.0 KAGAMI_BUILD=12 make package
```

Without `KAGAMI_VERSION` the DMG holds a development build, which never updates itself. Without
`NOTARY_PROFILE` it stops after signing and says so.

## The app icon

The source is `Resources/AppIcon.icon`, an Icon Composer document — `icon.json` names the bronze
gradient and the layer stack, and `Assets/` holds one SVG per layer: the mirror's face, its rim, and
the card it shows. Edit it in Icon Composer (it ships inside Xcode) or edit the SVGs by hand, then:

```bash
Scripts/make-icon.sh
```

That emits both products macOS needs, and both are committed so an ordinary `make app` needs no
Xcode:

| Product | Read via | Used by |
|---|---|---|
| `Resources/Assets.car` | `CFBundleIconName` | macOS 26, which renders the layers as Liquid Glass |
| `Resources/AppIcon.icns` | `CFBundleIconFile` | macOS 14 and 15, which get a flat rendering |
