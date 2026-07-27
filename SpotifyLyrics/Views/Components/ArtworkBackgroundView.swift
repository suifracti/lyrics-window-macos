import SwiftUI

/// Shared track-bound background used by both main-window arrangements.
struct ArtworkBackgroundView: View {
    @ObservedObject var state: PlaybackState

    var body: some View {
        TrackBackdropView(
            track: state.currentTrack,
            identity: state.currentTrackIdentity,
            isLiveTrack: state.hasLiveTrack
        )
    }
}
