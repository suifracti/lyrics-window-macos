# macOS Lyrics Companion

A native macOS lyrics companion built with SwiftUI and Xcode. The current working baseline is the V3 main-window experience; experimental V4 design material is kept under `docs/` and is not treated as the runtime baseline.

## Build

```sh
xcodebuild -project SpotifyLyrics.xcodeproj \
  -scheme SpotifyLyrics \
  -configuration Debug \
  -derivedDataPath /tmp/macos-lyrics-companion-deriveddata \
  CODE_SIGNING_ALLOWED=NO build
```

## Tests

The repository contains focused shell contracts under `Tests/`, including V3 lyric readability, ruby/reading layout, transitions, backdrop, cover layout, and visual polish checks. Run an individual contract with:

```sh
bash Tests/v3_lyric_readability_contract.sh
```

## Repository hygiene

Build products, local archives, credentials, model files, temporary audio, databases, and external reference checkouts are intentionally ignored. Runtime credentials belong in macOS Keychain or local ignored configuration and must not be committed.

## Project workflow

- AI agents and collaborators must read [`AGENTS.md`](AGENTS.md) first.
- The full local build, archive, branch, and release workflow is in [`docs/DEVELOPMENT_WORKFLOW.md`](docs/DEVELOPMENT_WORKFLOW.md).
- Check the current source version with `git status`, `git rev-parse HEAD`, `git rev-parse main`, and `git rev-parse origin/main`.
- The standard Debug build is the command shown above; the documented core contract entry is `bash Tests/v3_lyric_readability_contract.sh`.
- This repository currently has no formal Release or SemVer tag.
