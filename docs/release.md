# Release

How a build reaches a user. The local development loop is in [development.md](development.md);
the signing identity itself is in [signing.md](signing.md).

## Packaging a DMG locally

```sh
./Scripts/build-dmg.sh            # -> build/Tinycast-<version>.dmg (version from project.yml)
./Scripts/build-dmg.sh 0.5.7      # -> build/Tinycast-0.5.7.dmg
```

It builds a Release `Tinycast.app` signed with `Tinycast Self-Signed` and packs it with an
`/Applications` symlink. Official per-channel releases are built by CI, below.

## Signing & Gatekeeper

Both local builds and CI releases sign with the same stable `Tinycast Self-Signed` identity, not an
Apple Developer ID — so macOS quarantines a directly-downloaded DMG. The Homebrew cask strips that
automatically; direct downloaders run `xattr -dr com.apple.quarantine "…/Tinycast.app"` once. Full
details in [signing.md](signing.md).

## How the in-app updater consumes a release

Every release publishes two assets from one build: `Tinycast-<version>.dmg`, which people download by
hand and which the cask installs, and `Tinycast-<version>.zip`, which the in-app updater installs. The
zip is produced with `ditto -c -k --keepParent --sequesterRsrc` — the only zip that leaves the code
signature verifiable, which matters because the updater refuses any bundle whose signature does not
prove it is ours.


Three things a release must keep true, or the updater skips it:

- **It carries a `.zip` asset this Mac can run.** A DMG-only release is not installable and is not
  offered.
- **The tag parses as `vMAJOR.MINOR.PATCH` or `vMAJOR.MINOR.PATCH-beta.N`,** and agrees with the
  `prerelease` flag. A tag of any other shape is treated as mis-published and skipped.
- **It is not a draft.**

**Both casks declare `auto_updates true`.** That is Homebrew's flag for an app that manages its own
version, and it is what keeps `brew update && brew upgrade` from fighting an app that updated itself:
brew never reports Tinycast outdated, never re-downloads it, and never rolls a self-updated copy back.
Removing that line would reintroduce exactly those three problems. See
[features/updates.md](features/updates.md).

## Pull request review

There is no CI workflow. CodeRabbit reviews every PR against `.coderabbit.yaml`: it runs SwiftLint
with `.swiftlint.yml`, annotates the diff and applies the pre-merge checks. It is a reviewer, not a
gate — it neither runs the harnesses nor builds the app, so the whole bar in
[testing.md](testing.md#definition-of-done) is run locally before a PR is opened.

## Releasing

`.github/workflows/release.yml` builds and publishes a DMG from GitHub Actions, no local machine
needed. Run it from the **personal-fork** branch (`Release` → **Use workflow from** → `personal-fork` → **Run workflow**) — the workflow refuses any other branch — and pick:

- **channel** — `beta` or `stable`. Each builds a distinct app (`Tinycast Beta.app` / `Tinycast.app`)
  with its own bundle id, alongside the local `Tinycast Dev.app`. Beta gets an auto-incrementing
  `-beta.N` suffix (`N` = the Actions run number) so re-running never collides; stable ships the
  version as-is.
- **version** — base semver, e.g. `0.2.0`.

It builds on a `macos-26` runner with Xcode 26 and publishes a GitHub Release tagged
`v<full-version>` with a versioned DMG and zip asset, marked prerelease for beta. On success it also
bumps the matching cask in the tap and announces the release on Discord.

The job pins `ARCHS` explicitly and asserts the slice on *every*
shipping binary — the app and the bundled `ClipboardTextHelper`: trusting `ARCHS_STANDARD` is what
shipped a thin arm64 build to Intel users once already, and it also keeps the Apple silicon download
from silently gaining a slice it never needs.

### Release notes

`Scripts/release-notes.sh` composes the release body, and CI runs it just before `gh release create`.
It is safe to run by hand against any tag — it only reads:

```sh
CHANNEL=beta TAG=v0.9.13-beta.61 ./Scripts/release-notes.sh /tmp/body.md /tmp/discord.md
```

The changelog itself comes from GitHub's own release-notes API, which lists every merged PR with its
author and number — so contributors are credited without anyone maintaining a `CHANGELOG.md`, and
without Conventional Commits. **Nothing is ever committed to this repo**: the tag is created
server-side by `gh release create`, and no release, bot or version-bump commit exists.

Two details the script exists for:

- **The previous tag is picked per channel.** Beta and stable tags interleave on `main` — the same
  commit can carry both — so "the previous release" is only ever right within one channel. A stable
  release therefore spans every beta since the last stable.
- **The body is split by `<!-- tinycast:install -->`.** Everything above it is the changelog;
  everything below is the Homebrew and quarantine text, which only a download page needs. The update
  window cuts at that marker — see [features/updates.md](features/updates.md). Full PR URLs are
  shortened to `#304`, which still autolinks on the web and fits a 460pt window.

The Discord announcement carries the same changelog, truncated to fit Discord's component limit, and
pings `@everyone`.

### Homebrew tap automation

Each job's final step rewrites the `version` + `sha256` of its cask (`tinycast` or
`tinycast@beta`) in the [`homebrew-personal`](https://github.com/aang-dev-ag/homebrew-personal) tap
and pushes. It needs a `HOMEBREW_TAP_TOKEN` repo secret — a fine-grained PAT with **Contents:
read/write** on the tap repo. Without the secret the step logs a warning and skips; the release still
publishes. The `sed` is anchored to `^  version` / `^  sha256`, so a cask's two-space indent on those
lines is load-bearing.

