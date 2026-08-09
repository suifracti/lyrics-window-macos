import CoreGraphics
import Foundation

/// Geometry shared by the V3 foreground and backdrop. The view layer is
/// intentionally responsible only for rendering these already-safe values;
/// this keeps window resizing from turning a readable layout into an overflow.
enum V3ResponsiveGeometry {
    struct ColumnSplit: Equatable {
        let artwork: CGFloat
        let lyrics: CGFloat
        let gap: CGFloat
    }

    struct AdaptiveSplitMetrics: Equatable {
        let horizontalPadding: CGFloat
        let verticalPadding: CGFloat
        let contentWidth: CGFloat
        let availableHeight: CGFloat
        let artworkWidth: CGFloat
        let lyricsWidth: CGFloat
        let gap: CGFloat
        let coverSize: CGFloat
        let reservedTrackChromeHeight: CGFloat
    }

    /// One continuous geometry model for every horizontal V3 layout. The old
    /// wide/medium implementations used unrelated ratios and let artwork scale
    /// resize the entire column, so crossing 1080pt could move the cover by
    /// hundreds of points. Here only the cover occupancy responds to the user
    /// scale; column allocation and padding interpolate with the canvas.
    static func adaptiveSplitMetrics(
        canvasSize: CGSize,
        artworkScale: CGFloat
    ) -> AdaptiveSplitMetrics {
        let width = finitePositive(canvasSize.width)
        let height = finitePositive(canvasSize.height)
        let interpolation = min(1, max(0, (width - 800) / 560))
        let horizontalPadding = interpolate(from: 32, to: 64, progress: interpolation)
        let verticalPadding = interpolate(from: 28, to: 34, progress: interpolation)
        let gap = interpolate(from: 24, to: 28, progress: interpolation)
        let contentWidth = max(1, width - horizontalPadding * 2)
        let availableHeight = max(1, height - verticalPadding * 2)
        let artworkRatio = interpolate(from: 0.40, to: 0.43, progress: interpolation)
        let split = splitColumns(
            containerWidth: contentWidth,
            requestedArtworkRatio: artworkRatio,
            gap: gap,
            minimumArtworkWidth: min(220, contentWidth * 0.30),
            minimumLyricsWidth: min(280, contentWidth * 0.36)
        )

        // Metadata, progress, time labels, playback buttons and their spacing
        // keep a fixed vertical budget. This is what prevents a 140% cover
        // from pushing transport controls below a short wide window.
        let reservedTrackChromeHeight = min(196, max(0, availableHeight - 1))
        let maximumCover = min(
            max(1, split.artwork - 12),
            max(1, availableHeight - reservedTrackChromeHeight),
            620
        )
        let normalizedScale = min(1, max(0, (finiteValue(artworkScale) - 0.8) / 0.6))
        let coverOccupancy = interpolate(from: 0.70, to: 1.0, progress: normalizedScale)
        let coverSize = max(1, maximumCover * coverOccupancy)

        return AdaptiveSplitMetrics(
            horizontalPadding: horizontalPadding,
            verticalPadding: verticalPadding,
            contentWidth: contentWidth,
            availableHeight: availableHeight,
            artworkWidth: split.artwork,
            lyricsWidth: split.lyrics,
            gap: split.gap,
            coverSize: coverSize,
            reservedTrackChromeHeight: reservedTrackChromeHeight
        )
    }

    static func boundedCoverSize(
        availableWidth: CGFloat,
        availableHeight: CGFloat,
        desiredSize: CGFloat,
        minimum: CGFloat = 1,
        maximum: CGFloat = .greatestFiniteMagnitude
    ) -> CGFloat {
        let width = finitePositive(availableWidth)
        let height = finitePositive(availableHeight)
        let desired = finitePositive(desiredSize)
        let lowerBound = finitePositive(minimum)
        let upperBound = min(width, height, finitePositive(maximum))

        return min(upperBound, max(lowerBound, desired))
    }

    static func splitColumns(
        containerWidth: CGFloat,
        requestedArtworkRatio: CGFloat,
        gap: CGFloat,
        minimumArtworkWidth: CGFloat,
        minimumLyricsWidth: CGFloat
    ) -> ColumnSplit {
        let width = finiteNonNegative(containerWidth)
        let resolvedGap = min(width, finiteNonNegative(gap))
        let remaining = max(0, width - resolvedGap)
        let artworkMinimum = min(remaining, finiteNonNegative(minimumArtworkWidth))
        let lyricsMinimum = min(remaining, finiteNonNegative(minimumLyricsWidth))
        let ratio = min(1, max(0, finiteNonNegative(requestedArtworkRatio)))

        guard remaining > 0 else {
            return ColumnSplit(artwork: 0, lyrics: 0, gap: resolvedGap)
        }

        // Honour both minimums whenever the container can hold them. If it
        // cannot, preserve the requested ratio without producing negatives.
        let artwork: CGFloat
        if artworkMinimum + lyricsMinimum <= remaining {
            let preferred = remaining * ratio
            artwork = min(remaining - lyricsMinimum, max(artworkMinimum, preferred))
        } else {
            artwork = min(remaining, max(0, remaining * ratio))
        }

        return ColumnSplit(
            artwork: artwork,
            lyrics: max(0, remaining - artwork),
            gap: resolvedGap
        )
    }

    /// Returns a fully visible, aspect-preserving artwork rect for the stage
    /// presentation. The rect is clamped to a safe canvas region, so a large
    /// scale value can make the artwork larger without turning it into a crop.
    static func stageArtworkRect(
        canvasSize: CGSize,
        artworkAspectRatio: CGFloat,
        requestedScale: CGFloat,
        position: String,
        horizontalMargin: CGFloat = 18,
        topInset: CGFloat = 16,
        bottomInset: CGFloat = 16
    ) -> CGRect {
        let canvasWidth = finitePositive(canvasSize.width)
        let canvasHeight = finitePositive(canvasSize.height)
        let margin = min(canvasWidth / 2, finiteNonNegative(horizontalMargin))
        let top = min(canvasHeight, finiteNonNegative(topInset))
        let bottom = min(max(0, canvasHeight - top), finiteNonNegative(bottomInset))
        let safeWidth = max(1, canvasWidth - margin * 2)
        let safeHeight = max(1, canvasHeight - top - bottom)
        let aspect = min(4, max(0.25, finiteValue(artworkAspectRatio)))

        var width: CGFloat
        var height: CGFloat
        if safeWidth / safeHeight > aspect {
            height = safeHeight
            width = height * aspect
        } else {
            width = safeWidth
            height = width / aspect
        }

        let normalizedScale = min(1, max(0, (finiteValue(requestedScale) - 0.8) / 0.6))
        let occupancy = 0.72 + normalizedScale * 0.28
        width *= occupancy
        height *= occupancy

        // Re-clamp after scaling while preserving the source ratio.
        if width > safeWidth {
            width = safeWidth
            height = width / aspect
        }
        if height > safeHeight {
            height = safeHeight
            width = height * aspect
        }

        let preferredX: CGFloat
        switch position {
        case "right": preferredX = canvasWidth * 0.72
        case "center": preferredX = canvasWidth * 0.50
        default: preferredX = canvasWidth * 0.28
        }

        let halfWidth = width / 2
        let minimumX = margin + halfWidth
        let maximumX = max(minimumX, canvasWidth - margin - halfWidth)
        let centerX = min(maximumX, max(minimumX, preferredX))
        let safeCenterY = top + safeHeight / 2
        let halfHeight = height / 2
        let minimumY = top + halfHeight
        let maximumY = max(minimumY, canvasHeight - bottom - halfHeight)
        let centerY = min(maximumY, max(minimumY, safeCenterY))

        return CGRect(
            x: centerX - halfWidth,
            y: centerY - halfHeight,
            width: width,
            height: height
        )
    }

    private static func finitePositive(_ value: CGFloat) -> CGFloat {
        guard value.isFinite else { return 1 }
        return max(1, value)
    }

    private static func finiteValue(_ value: CGFloat) -> CGFloat {
        guard value.isFinite else { return 0 }
        return value
    }

    private static func finiteNonNegative(_ value: CGFloat) -> CGFloat {
        guard value.isFinite else { return 0 }
        return max(0, value)
    }

    private static func interpolate(from start: CGFloat, to end: CGFloat, progress: CGFloat) -> CGFloat {
        start + (end - start) * min(1, max(0, progress))
    }
}
