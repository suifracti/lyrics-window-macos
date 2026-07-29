# Settings Window V1 Implementation Plan

> **For agentic workers:** Execute this plan inline with the existing repository; keep the app's current playback, lyrics, provider, alignment, and window visuals unchanged.

**Goal:** Centralize user configuration in a native macOS SwiftUI Settings window with a Sidebar, persist provider/display choices, and expose safe database/OAuth diagnostics without changing the main lyrics window.

**Architecture:** `AppSettingsStore` is the single UserDefaults-backed configuration boundary. `PlaybackState` observes it and maps provider IDs into the existing `LyricsSessionController`; Settings views never execute SQL or own provider instances. `SettingsDataController` owns asynchronous repository/index operations for the data and storage pages.

**Tech Stack:** SwiftUI macOS Settings scene, Combine, UserDefaults, existing actor-isolated SQLiteLyricsRepository, existing Keychain-backed SpotifyAuthorizationManager, shell contract tests, normal signed Debug xcodebuild.

## Global Constraints

- Do not modify the main window visual implementation, AI translation, alignment algorithms, editor/import features, or add providers.
- Preserve `mainWindowLayoutStyle` and `spotify.clientID`; keep access and refresh tokens in Keychain only.
- The legacy immersive split layout remains source-compatible and is labeled deprecated; it is not deleted.
- SQLite v2 stable-key merge is design-only in this phase; no destructive migration runs.
- Settings views call repository/controller APIs, never SQL directly.

### Task 1: Shared settings and provider configuration

**Files:**
- Create: `SpotifyLyrics/Settings/AppSettingsStore.swift`
- Create: `SpotifyLyrics/Settings/LyricsProviderConfiguration.swift`
- Modify: `SpotifyLyrics/Models/Models.swift`
- Modify: `SpotifyLyrics/Lyrics/LyricsSearchManager.swift`
- Modify: `SpotifyLyrics/Services/LyricsSessionController.swift`
- Modify: `SpotifyLyrics/Services/PlaybackState.swift`
- Test: `Tests/settings_contract.sh`

- [x] Add failing contract assertions for the shared keys, provider order, and runtime update API.
- [x] Run the contract and confirm it fails because the files/API do not exist.
- [x] Add `AppSettingsStore`, `LyricsProviderConfiguration`, and the persisted `DisplayPreferences` fields.
- [x] Make the lyrics manager snapshot its providers and let sessions update that snapshot without restarting playback.
- [x] Make `PlaybackState` observe one settings instance and inject the configured order while preserving test initializer compatibility.
- [x] Run the contract and focused existing contracts.

### Task 2: Settings scene and Sidebar pages

**Files:**
- Create: `SpotifyLyrics/Views/Settings/SettingsRootView.swift`
- Modify: `SpotifyLyrics/Main.swift`
- Modify: `SpotifyLyrics/Views/MainWindow/MainLyricsWindowView.swift`
- Modify: `SpotifyLyrics/Views/Components/SongSearchPopover.swift`
- Modify: `SpotifyLyrics/Spotify/SpotifyAuthorizationManager.swift`

- [x] Add the native `Settings` scene and shared environment objects.
- [x] Implement Sidebar categories and the General, Display, Spotify, Providers, Data, and Advanced pages.
- [x] Replace the search popover's full OAuth form with status plus `SettingsLink`.
- [x] Keep Client ID in the existing UserDefaults key, expose callback read-only, and add a safe authorization-state refresh method.
- [x] Wire launch, auto-search, display preference, layout, and window-state settings to the existing main path.

### Task 3: Storage and diagnostics boundary

**Files:**
- Create: `SpotifyLyrics/Settings/SettingsDataController.swift`
- Modify: `SpotifyLyrics/Persistence/LyricsRepository.swift`
- Modify: `SpotifyLyrics/Persistence/SQLiteLyricsRepository.swift`
- Modify: `SpotifyLyrics/Search/LocalLyricsIndex.swift`

- [x] Add repository-level statistics, backup, and lyric-cache clearing APIs with default protocol fallbacks.
- [x] Implement actor-isolated statistics, WAL checkpoint backup, and transactional lyric cache deletion.
- [x] Expose local index rebuild without changing file contents.
- [x] Add confirmation-gated UI actions and redacted diagnostic export.

### Task 4: Target membership, verification, and delivery

**Files:**
- Modify: `SpotifyLyrics.xcodeproj/project.pbxproj`
- Modify: `Tests/settings_contract.sh`

- [x] Add all new Swift sources to the SpotifyLyrics target and source group.
- [x] Run all existing shell contracts plus the settings contract.
- [x] Delete/rebuild the exact DerivedData path, verify codesign and process source, then perform real UI/settings checks.
- [x] Record diff/stat and commit only the implementation files and settings plan; leave pre-existing untracked artifacts untouched.
