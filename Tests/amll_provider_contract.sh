#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

TMP_DIR="$(mktemp -d /tmp/amll-provider.XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

swiftc -parse-as-library \
  SpotifyLyrics/Models/Models.swift \
  SpotifyLyrics/Lyrics/TrackIdentity.swift \
  SpotifyLyrics/Lyrics/AlignmentModels.swift \
  SpotifyLyrics/Lyrics/LyricsModels.swift \
  SpotifyLyrics/Lyrics/LRCParser.swift \
  SpotifyLyrics/Lyrics/AMLLLyricsProvider.swift \
  Tests/amll_provider_contract.swift \
  -o "$TMP_DIR/amll-provider-contract"

"$TMP_DIR/amll-provider-contract"

swiftc -parse-as-library \
  SpotifyLyrics/Settings/LyricsProviderConfiguration.swift \
  Tests/amll_provider_configuration_contract.swift \
  -o "$TMP_DIR/amll-provider-configuration-contract"

"$TMP_DIR/amll-provider-configuration-contract"
