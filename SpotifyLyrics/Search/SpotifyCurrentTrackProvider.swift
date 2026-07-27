import Foundation

// Compatibility shim: implementation lives in CurrentTrackResolver.swift.
// Spotify Desktop current-track resolution is not a free-text catalog search.
// Legacy SongSearchProvider clients should wrap via SongSearchManager's bridge
// or call TrackSearchProvider directly.
