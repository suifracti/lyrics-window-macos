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
