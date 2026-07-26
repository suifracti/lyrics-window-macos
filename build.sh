#!/bin/bash
set -e

echo "==> Compiling Swift sources..."
SDK_PATH=$(xcrun --show-sdk-path)

mkdir -p build/SpotifyLyrics.app/Contents/MacOS
mkdir -p build/SpotifyLyrics.app/Contents/Resources

swiftc \
    Sources/SpotifyLyrics/Models/Models.swift \
    Sources/SpotifyLyrics/Services/MockData.swift \
    Sources/SpotifyLyrics/Services/PlaybackState.swift \
    Sources/SpotifyLyrics/Windows/WindowManager.swift \
    Sources/SpotifyLyrics/Views/LyricsViews.swift \
    Sources/SpotifyLyrics/Main.swift \
    -sdk "$SDK_PATH" \
    -target arm64-apple-macosx14.0 \
    -O \
    -o build/SpotifyLyrics.app/Contents/MacOS/SpotifyLyrics

cat << 'EOF' > build/SpotifyLyrics.app/Contents/Info.plist
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>SpotifyLyrics</string>
    <key>CFBundleIdentifier</key>
    <string>com.spotifylyrics.app</string>
    <key>CFBundleName</key>
    <string>SpotifyLyrics</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

rm -f SpotifyLyricsBinary

ABS_PATH="$(cd build && pwd)/SpotifyLyrics.app"
echo "==> Build and Packaging Successful!"
echo "APP_PATH: $ABS_PATH"
