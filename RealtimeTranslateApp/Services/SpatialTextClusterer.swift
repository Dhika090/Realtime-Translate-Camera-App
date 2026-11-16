import Foundation
import CoreGraphics

// MARK: - Character CJK Extension

extension Character {
    /// Indicates whether this character belongs to CJK (Chinese, Japanese, Korean) script ranges.
    public var isCJK: Bool {
        for scalar in unicodeScalars {
            switch scalar.value {
            case 0x4E00...0x9FFF,   // CJK Unified Ideographs
                 0x3400...0x4DBF,   // CJK Unified Ideographs Extension A
                 0x20000...0x2A6DF, // CJK Extension B
                 0x2A700...0x2B73F, // CJK Extension C
                 0x2B740...0x2B81F, // CJK Extension D
                 0x2B820...0x2CEAF, // CJK Extension E
                 0xF900...0xFAFF,   // CJK Compatibility Ideographs
                 0x2F800...0x2FA1F, // CJK Compatibility Ideographs Supplement
                 0x3040...0x309F,   // Hiragana
                 0x30A0...0x30FF,   // Katakana
                 0xAC00...0xD7AF,   // Hangul Syllables
                 0x3000...0x303F,   // CJK Symbols and Punctuation
                 0xFF00...0xFFEF:   // Halfwidth and Fullwidth Forms
                return true
            default:
                continue
            }
        }
        return false
    }
}

// MARK: - SpatialTextClusterer

/// Clusters spatially adjacent lines of OCR text into semantic text blocks.
///
/// Operates on Vision normalized coordinates (0...1) where origin (0,0) is bottom-left.
/// Top-to-bottom reading order corresponds to descending Y values.
public final class SpatialTextClusterer: Sendable {

    public init() {}

    /// Clusters OCR lines into semantic text blocks based on vertical adjacency and horizontal overlap.
    ///
    /// - Parameters:
    ///   - lines: An array of recognized `OCRLine` items with normalized bounding boxes.
    ///   - lineSpacingThreshold: Maximum vertical distance between adjacent lines to be clustered together.
    /// - Returns: An array of `DetectedTextBlock` sorted in top-to-bottom, left-to-right reading order.
    public func cluster(
        lines: [OCRLine],
        lineSpacingThreshold: CGFloat = 0.04
    ) -> [DetectedTextBlock] {
        guard !lines.isEmpty else { return [] }

        if lines.count == 1 {
            let single = lines[0]
            return [
                DetectedTextBlock(
                    rawLines: [single.text],
                    mergedText: single.text.trimmingCharacters(in: .whitespacesAndNewlines),
                    boundingBox: single.boundingBox
                )
            ]
        }

        // Build connected components using Disjoint Set Union (DSU)
        let dsu = DisjointSet(size: lines.count)

        for i in 0..<lines.count {
            for j in (i + 1)..<lines.count {
                if areVerticallyAdjacentAndOverlap(lines[i], lines[j], threshold: lineSpacingThreshold) {
                    dsu.union(i, j)
                }
            }
        }

        // Group lines by their connected component root
        var groups: [Int: [OCRLine]] = [:]
        for i in 0..<lines.count {
            let root = dsu.find(i)
            groups[root, default: []].append(lines[i])
        }

        // Process each group into a DetectedTextBlock
        var blocks: [DetectedTextBlock] = []
        for (_, groupLines) in groups {
            // Sort lines in top-to-bottom reading order (descending Y in Vision coords)
            let sortedLines = groupLines.sorted { lineA, lineB in
                let boxA = lineA.boundingBox
                let boxB = lineB.boundingBox
                let verticalDelta = abs(boxA.midY - boxB.midY)
                let minHeight = min(boxA.height, boxB.height)

                // If on the same horizontal row, sort left-to-right (ascending X)
                if verticalDelta < minHeight * 0.5 {
                    return boxA.minX < boxB.minX
                }
                // Otherwise sort top-to-bottom (descending Y in Vision bottom-left coords)
                return boxA.midY > boxB.midY
            }

            // Union bounding boxes
            let unionBox = sortedLines.dropFirst().reduce(sortedLines[0].boundingBox) {
                $0.union($1.boundingBox)
            }

            // Merge text (handling CJK without extra spaces, Latin with spaces)
            let rawLines = sortedLines.map { $0.text }
            let mergedText = mergeTextLines(sortedLines)

            blocks.append(
                DetectedTextBlock(
                    rawLines: rawLines,
                    mergedText: mergedText,
                    boundingBox: unionBox
                )
            )
        }

        // Sort resulting blocks in reading order: top-to-bottom, then left-to-right
        blocks.sort { blockA, blockB in
            let boxA = blockA.boundingBox
            let boxB = blockB.boundingBox
            let verticalDelta = abs(boxA.midY - boxB.midY)
            let minHeight = min(boxA.height, boxB.height)

            if verticalDelta < minHeight * 0.5 {
                return boxA.minX < boxB.minX
            }
            return boxA.midY > boxB.midY
        }

        return blocks
    }

    // MARK: - Private Helpers

    /// Checks if two lines have horizontal overlap and are within the vertical distance threshold.
    private func areVerticallyAdjacentAndOverlap(
        _ lineA: OCRLine,
        _ lineB: OCRLine,
        threshold: CGFloat
    ) -> Bool {
        let boxA = lineA.boundingBox
        let boxB = lineB.boundingBox

        // Horizontal overlap check: intersection width along X axis > 0
        let hOverlap = min(boxA.maxX, boxB.maxX) - max(boxA.minX, boxB.minX)
        guard hOverlap > 0 else { return false }

        // Vertical distance check: gap between non-overlapping intervals along Y axis
        let vDistance = max(0, max(boxA.minY, boxB.minY) - min(boxA.maxY, boxB.maxY))
        return vDistance <= threshold
    }

    /// Merges an array of sorted OCRLines into a coherent string.
    /// Joins with space for Latin / alphabetical scripts, joins directly for CJK scripts.
    private func mergeTextLines(_ lines: [OCRLine]) -> String {
        guard let first = lines.first else { return "" }

        var merged = first.text.trimmingCharacters(in: .whitespacesAndNewlines)

        for nextLine in lines.dropFirst() {
            let trimmedNext = nextLine.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedNext.isEmpty else { continue }

            if shouldJoinWithoutSpace(merged, trimmedNext) {
                merged += trimmedNext
            } else {
                merged += " " + trimmedNext
            }
        }

        return merged
    }

    /// Determines whether two consecutive strings should be joined directly without an intervening space.
    private func shouldJoinWithoutSpace(_ line1: String, _ line2: String) -> Bool {
        guard !line1.isEmpty, !line2.isEmpty else { return false }

        let hasCJK1 = line1.contains { $0.isCJK }
        let hasCJK2 = line2.contains { $0.isCJK }

        // If both lines contain CJK characters
        if hasCJK1 && hasCJK2 {
            return true
        }

        // If the boundary characters between the two lines are CJK
        if let last = line1.last, let first = line2.first, (last.isCJK || first.isCJK) {
            return true
        }

        return false
    }
}

// MARK: - Disjoint Set Union (DSU)

private final class DisjointSet {
    private var parent: [Int]

    init(size: Int) {
        parent = Array(0..<size)
    }

    func find(_ x: Int) -> Int {
        if parent[x] != x {
            parent[x] = find(parent[x])
        }
        return parent[x]
    }

    func union(_ x: Int, _ y: Int) {
        let rootX = find(x)
        let rootY = find(y)
        if rootX != rootY {
            parent[rootX] = rootY
        }
    }
}
