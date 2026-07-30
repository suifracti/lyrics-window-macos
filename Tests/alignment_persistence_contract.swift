import Foundation

struct PersistenceTestError: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}

@main
struct AlignmentPersistenceContract {
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SpotifyLyricsAlignmentPersistence-\(UUID().uuidString)")
        let databaseURL = root.appendingPathComponent("SpotifyLyrics.sqlite3")
        let provenanceURL = root.appendingPathComponent("AlignmentProvenance", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let repository = SQLiteLyricsRepository(databaseURL: databaseURL, alignmentProvenanceDirectory: provenanceURL)
        try await repository.prepare()
        let track = Track(id: "alignment-test", title: "TEST Alignment", artist: "TEST Artist", album: "TEST Album", duration: 10, spotifyId: "alignment-test")
        let identity = TrackIdentity(track: track)
        let plain = LyricsDocument(
            identity: identity,
            title: track.title,
            artist: track.artist,
            album: track.album,
            duration: track.duration,
            lines: [
                LyricLine(timestamp: 0, originalText: "最初の歌", romajiText: "saisho no uta", kanaText: "さいしょのうた"),
                LyricLine(timestamp: 0, originalText: "最後の歌", romajiText: "saigo no uta", kanaText: "さいごのうた")
            ],
            isSynchronized: false,
            source: .manualCreate,
            confidence: 1
        )
        let parentSave = try await repository.save(track: track, identity: identity, document: plain)
        guard let parentID = parentSave.versionID, let parentHash = parentSave.sourceContentHash else {
            throw PersistenceTestError(message: "plain parent not saved")
        }

        let alignedLines = [
            AlignedLyricLine(
                originalText: "最初の歌", kanaText: "さいしょのうた", romajiText: "saisho no uta",
                startTime: 2, endTime: 3, confidence: 0.95, status: .aligned,
                evidence: AlignmentLineEvidence(kind: .directSpeech, segmentStartIndex: 1, segmentEndIndex: 1, transcriptConfidence: 0.95, matchScore: 0.95, note: "TEST direct")
            ),
            AlignedLyricLine(
                originalText: "最後の歌", kanaText: "さいごのうた", romajiText: "saigo no uta",
                startTime: 8, endTime: 9, confidence: 0.95, status: .aligned,
                evidence: AlignmentLineEvidence(kind: .directSpeech, segmentStartIndex: 2, segmentEndIndex: 2, transcriptConfidence: 0.95, matchScore: 0.95, note: "TEST direct")
            )
        ]
        let timed = LyricsDocument(
            identity: identity,
            title: track.title,
            artist: track.artist,
            album: track.album,
            duration: track.duration,
            lines: alignedLines.map { $0.asLyricLine() },
            isSynchronized: true,
            source: .automaticAlignment,
            confidence: 0.95
        )
        let report = AlignmentReport(
            identity: identity,
            lines: alignedLines,
            audioDuration: 10,
            audioSHA256: String(repeating: "a", count: 64),
            modelID: "TEST-transcript",
            usedVocalsStem: false,
            overallConfidence: 0.95,
            sourceVersionID: parentID,
            sourceContentHash: parentHash,
            parameters: AlignmentParameters(recognizerID: "TEST-transcript")
        )
        let request = AlignmentPersistenceRequest(
            track: track,
            identity: identity,
            parentVersionID: parentID,
            parentSourceContentHash: parentHash,
            document: timed,
            report: report
        )
        let saved = try await repository.saveAlignedVersion(request)
        guard let alignedID = saved.versionID else {
            throw PersistenceTestError(message: "aligned child not inserted: \(saved.disposition)")
        }
        if case .inserted = saved.disposition { } else {
            throw PersistenceTestError(message: "aligned child not inserted: \(saved.disposition)")
        }
        let sidecar = provenanceURL.appendingPathComponent("\(alignedID.uuidString).json")
        precondition(FileManager.default.fileExists(atPath: sidecar.path))
        let sidecarText = try String(contentsOf: sidecar, encoding: .utf8)
        precondition(sidecarText.contains("TEST-transcript"))
        precondition(!sidecarText.contains("最初の歌"), "sidecar duplicated lyric text")
        precondition(!sidecarText.contains("originalText"), "sidecar duplicated lyric fields")
        precondition(!sidecarText.contains("surface"), "sidecar stored transcript tokens")

        let duplicate = try await repository.saveAlignedVersion(request)
        if case .duplicate = duplicate.disposition { } else {
            throw PersistenceTestError(message: "duplicate alignment was not deduplicated")
        }
        precondition(duplicate.versionID == alignedID)

        let restarted = SQLiteLyricsRepository(databaseURL: databaseURL, alignmentProvenanceDirectory: provenanceURL)
        try await restarted.prepare()
        let restored = try await restarted.loadBestStored(track: track, identity: identity)
        precondition(restored?.versionID == alignedID)
        precondition(restored?.document.isSynchronized == true)
        precondition(restored?.document.lines.map(\.timestamp) == [2, 8])
        precondition(restored?.alignmentProvenanceAvailability == .available)
        try FileManager.default.removeItem(at: sidecar)
        let missingProvenance = try await restarted.loadBestStored(track: track, identity: identity)
        precondition(missingProvenance?.alignmentProvenanceAvailability == .unavailable)
        let duplicateWithoutSidecar = try await restarted.saveAlignedVersion(request)
        if case .duplicate = duplicateWithoutSidecar.disposition { } else {
            throw PersistenceTestError(message: "missing-sidecar retry created an unexpected alignment version")
        }
        let duplicateAvailability = await restarted.alignmentProvenanceAvailability(versionID: alignedID)
        precondition(duplicateAvailability == .unavailable)
        _ = try AlignmentProvenanceStore(directory: provenanceURL).write(
            versionID: alignedID,
            parentVersionID: parentID,
            report: report
        )

        let lowLine = AlignedLyricLine(
            originalText: "最初の歌", kanaText: "さいしょのうた", romajiText: "saisho no uta",
            startTime: 2, endTime: 3, confidence: 0.2, status: .interpolated,
            evidence: AlignmentLineEvidence(kind: .boundedInterpolation, segmentStartIndex: 1, segmentEndIndex: 2, note: "TEST low")
        )
        let lowReport = AlignmentReport(
            identity: identity,
            lines: [lowLine, alignedLines[1]],
            audioDuration: 10,
            audioSHA256: String(repeating: "b", count: 64),
            modelID: "TEST-transcript",
            usedVocalsStem: false,
            overallConfidence: 0.2,
            sourceVersionID: parentID,
            sourceContentHash: parentHash
        )
        let lowDoc = LyricsDocument(
            identity: identity, title: track.title, artist: track.artist, album: track.album, duration: 10,
            lines: [lowLine.asLyricLine(), alignedLines[1].asLyricLine()],
            isSynchronized: true, source: .automaticAlignment, confidence: 0.2
        )
        let lowSave = try await restarted.saveAlignedVersion(AlignmentPersistenceRequest(
            track: track, identity: identity, parentVersionID: parentID, parentSourceContentHash: parentHash,
            document: lowDoc, report: lowReport, lockResult: true
        ))
        if case .rejected = lowSave.disposition { } else { throw PersistenceTestError(message: "low-confidence alignment was locked") }

        try await restarted.deleteLyricsVersion(versionID: alignedID)
        precondition(!FileManager.default.fileExists(atPath: sidecar.path))
        let restoredParent = try await restarted.loadEditableVersion(versionID: parentID, track: track, identity: identity)
        let deletedChild = try await restarted.loadEditableVersion(versionID: alignedID, track: track, identity: identity)
        precondition(restoredParent != nil)
        precondition(deletedChild == nil)
        print("alignment persistence contract passed (TEST data; SQLite v3 + sidecar)")
    }
}
