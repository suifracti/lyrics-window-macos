#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h}/.."
FILE="$ROOT/SpotifyLyrics/Views/MainWindow/AppleMusicImmersiveV3WindowView.swift"

for needle in \
  'translationMenuContent' \
  '重新翻译' \
  '锁定当前版本' \
  '删除当前版本' \
  'selectTranslation' \
  'lockSelectedTranslation' \
  'deleteSelectedTranslation'; do
  grep -F "$needle" "$FILE" >/dev/null
done

print "translation UI contract passed"
