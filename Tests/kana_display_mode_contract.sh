#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MODELS="$ROOT/SpotifyLyrics/Models/Models.swift"
PREFERENCES="$ROOT/SpotifyLyrics/Views/Components/LyricsPreferencesPopover.swift"
LINE="$ROOT/SpotifyLyrics/Views/Components/LyricLineView.swift"

grep -Eq 'enum KanaDisplayMode' "$MODELS"
grep -Eq 'independentLine|inlineRuby|hidden' "$MODELS"
grep -Eq 'kanaDisplayMode' "$PREFERENCES"
grep -Eq 'Picker\("假名显示模式"' "$PREFERENCES"
grep -Eq 'independentLine' "$LINE"
grep -Eq 'inlineRuby' "$LINE"

TMP_DIR="$(mktemp -d /tmp/kana-display-mode-contract.XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

cat > "$TMP_DIR/main.swift" <<'SWIFT'
import Foundation

@main
struct KanaDisplayModeContract {
    static func main() {
        var preferences = DisplayPreferences()
        precondition(preferences.kanaDisplayMode == .hidden)
        precondition(!preferences.showKana)

        preferences.showKana = true
        precondition(preferences.kanaDisplayMode == .independentLine)
        precondition(preferences.showKana)

        let independent = DisplayPreferences(kanaDisplayMode: .independentLine)
        precondition(independent.showKana)
        precondition(independent.kanaDisplayMode.title == "独立行")
        precondition(independent.kanaDisplayMode.detail.contains("整行"))

        print("kana display mode contract passed")
    }
}
SWIFT

swiftc -parse-as-library "$MODELS" "$TMP_DIR/main.swift" -o "$TMP_DIR/kana-display-mode-contract"
"$TMP_DIR/kana-display-mode-contract"

echo 'PASS: kana display mode contract'
