import Combine
import Foundation

@MainActor
public final class LyricsSessionController: ObservableObject {
    @Published public private(set) var state: LyricsLoadState = .idle
    @Published public private(set) var lyrics: [LyricLine] = []
    @Published public private(set) var isSynchronized = true
    @Published public private(set) var activeIdentity: TrackIdentity?
    @Published public private(set) var revision: UInt64 = 0

    private let provider: LyricsProvider
    private var requestTask: Task<Void, Never>?
    private var automaticRecoveryRetryIdentity: TrackIdentity?

    public init(provider: LyricsProvider) {
        self.provider = provider
    }

    deinit {
        requestTask?.cancel()
    }

    public func begin(track: Track, identity: TrackIdentity) {
        cancelCurrentRequest()
        revision &+= 1
        let requestRevision = revision
        if activeIdentity != identity {
            automaticRecoveryRetryIdentity = nil
        }
        activeIdentity = identity
        lyrics = []
        isSynchronized = true
        state = .loading(identity)

        requestTask = Task { [weak self, provider] in
            let result = await provider.lookup(track: track, identity: identity)
            guard !Task.isCancelled else { return }
            self?.apply(
                result,
                identity: identity,
                requestRevision: requestRevision
            )
        }
    }

    public func retry(track: Track, identity: TrackIdentity) {
        begin(track: track, identity: identity)
    }

    /// Performs at most one automatic retry for a network failure belonging
    /// to the active Track identity. Manual retry remains available through
    /// `retry(track:identity:)` and does not alter playback state.
    @discardableResult
    public func retryAfterNetworkRecovery(track: Track, identity: TrackIdentity) -> Bool {
        guard activeIdentity == identity,
              case .failed(let failedIdentity, .networkUnavailable) = state,
              failedIdentity == identity,
              automaticRecoveryRetryIdentity != identity else {
            return false
        }

        automaticRecoveryRetryIdentity = identity
        begin(track: track, identity: identity)
        return true
    }

    public func clear() {
        cancelCurrentRequest()
        revision &+= 1
        activeIdentity = nil
        automaticRecoveryRetryIdentity = nil
        lyrics = []
        isSynchronized = true
        state = .idle
    }

    public func enterMockPreview(lines: [LyricLine]) {
        cancelCurrentRequest()
        revision &+= 1
        activeIdentity = nil
        automaticRecoveryRetryIdentity = nil
        lyrics = lines
        isSynchronized = true
        state = .mockPreview
    }

    public func adopt(candidate: LyricsCandidate) {
        guard activeIdentity == candidate.identity else { return }
        guard !candidate.lines.isEmpty else {
            lyrics = []
            state = .noLyrics(candidate.identity)
            return
        }

        let document = LyricsDocument(
            identity: candidate.identity,
            title: candidate.title,
            artist: candidate.artist,
            album: candidate.album,
            duration: candidate.duration,
            lines: candidate.lines,
            isSynchronized: candidate.isSynchronized,
            source: candidate.source,
            confidence: candidate.confidence
        )
        lyrics = document.lines
        isSynchronized = document.isSynchronized
        state = .loaded(document)
    }

    private func apply(
        _ result: LyricsLookupResult,
        identity: TrackIdentity,
        requestRevision: UInt64
    ) {
        guard activeIdentity == identity, revision == requestRevision else { return }

        switch result {
        case .match(let document):
            guard document.identity == identity else {
                lyrics = []
                state = .failed(identity, .unknown("歌词身份与当前歌曲不一致"))
                return
            }
            lyrics = document.lines
            isSynchronized = document.isSynchronized
            state = document.lines.isEmpty ? .noLyrics(identity) : .loaded(document)
        case .candidates(let candidates):
            lyrics = []
            isSynchronized = true
            state = .candidates(identity, candidates)
        case .noLyrics:
            lyrics = []
            isSynchronized = true
            state = .noLyrics(identity)
        case .noMatch:
            lyrics = []
            isSynchronized = true
            state = .noMatch(identity)
        case .failed(let failure):
            lyrics = []
            isSynchronized = true
            state = .failed(identity, failure)
        }
    }

    private func cancelCurrentRequest() {
        requestTask?.cancel()
        requestTask = nil
    }
}
