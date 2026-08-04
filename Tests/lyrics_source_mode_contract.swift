import Foundation

private func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

@main
struct LyricsSourceModeContract {
    static func main() {
        require(
            LyricsSourceMode.standardFree.rawValue == "lyricsSourceMode.standardFree.v1",
            "standard free stable id"
        )
        require(
            LyricsSourceMode.experimentalFree.rawValue == "lyricsSourceMode.experimentalFree.v1",
            "experimental free stable id"
        )
        require(LyricsSourceMode.default == .standardFree, "default mode is standard free")
        require(!LyricsSourceMode.standardFree.allowsExperimentalProviders, "A blocks experimental")
        require(LyricsSourceMode.experimentalFree.allowsExperimentalProviders, "B allows experimental")

        require(LyricsProviderID.localFiles.policy.capabilityClass == .local, "local class")
        require(LyricsProviderID.lrclib.policy.capabilityClass == .openFree, "lrclib open free")
        require(
            LyricsProviderID.netEaseExperimental.policy.capabilityClass == .experimentalFree,
            "netease experimental"
        )
        require(
            LyricsProviderID.qqExperimental.policy.capabilityClass == .experimentalFree,
            "qq experimental"
        )
        require(LyricsDiscoverySite.utaNet.policy.capabilityClass == .discoveryOnly, "discovery only")
        require(LyricsDiscoverySite.utaNet.policy.allowsLyricsBody == false, "discovery never body")
        require(LyricsDiscoverySite.utaNet.policy.outboundOnly, "discovery outbound only")
        require(LyricsDiscoverySite.utaTime.policy.allowsLocalCache == false, "discovery no cache")
        require(LyricsDiscoverySite.awa.policy.allowsExport == false, "discovery no export")
        require(LyricsUserContentPolicy.policy.capabilityClass == .userContent, "user content class")
        require(LyricsUserContentPolicy.policy.allowedInStandardFree, "user content in A")
        require(LyricsUserContentPolicy.policy.allowedInExperimentalFree, "user content in B")
        require(!LyricsUserContentPolicy.policy.allowsAutomaticSearch, "user content not auto search")

        require(LyricsProviderID.lrclib.isAllowed(in: .standardFree), "lrclib in A")
        require(!LyricsProviderID.netEaseExperimental.isAllowed(in: .standardFree), "netease blocked in A")
        require(!LyricsProviderID.qqExperimental.isAllowed(in: .standardFree), "qq blocked in A")
        require(LyricsProviderID.netEaseExperimental.isAllowed(in: .experimentalFree), "netease in B")
        require(LyricsProviderID.qqExperimental.isAllowed(in: .experimentalFree), "qq in B")

        let allOn = LyricsProviderConfiguration.default
        let standardIDs = allOn.orderedEnabledIDs(for: .standardFree)
        require(standardIDs.contains(.localFiles), "A includes local")
        require(standardIDs.contains(.lrclib), "A includes lrclib")
        require(!standardIDs.contains(.netEaseExperimental), "A excludes netease")
        require(!standardIDs.contains(.qqExperimental), "A excludes qq")

        let experimentalIDs = allOn.orderedEnabledIDs(for: .experimentalFree)
        require(experimentalIDs.contains(.netEaseExperimental), "B includes netease")
        require(experimentalIDs.contains(.qqExperimental), "B includes qq")
        require(experimentalIDs.contains(.lrclib), "B still includes lrclib")

        // Preference-disabled experimental stays out even in mode B.
        var partial = LyricsProviderConfiguration.default
        partial.enabled.remove(.netEaseExperimental)
        require(
            !partial.orderedEnabledIDs(for: .experimentalFree).contains(.netEaseExperimental),
            "disabled experimental stays out of B"
        )

        require(LyricsDiscoverySite.awa.browserURL(query: "") != nil, "awa home")
        require(LyricsDiscoverySite.utaNet.browserURL(query: "あやふや みさき") != nil, "uta-net url")

        let rawIDs = LyricsProviderID.allCases.map(\.rawValue).joined(separator: ",")
        require(!rawIDs.lowercased().contains("musixmatch"), "no musixmatch id")
        require(!rawIDs.lowercased().contains("kugou"), "no kugou id")

        print("lyrics_source_mode_contract: PASS")
    }
}
