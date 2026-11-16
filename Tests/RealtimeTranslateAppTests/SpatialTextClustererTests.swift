import XCTest
@testable import RealtimeTranslateApp

final class SpatialTextClustererTests: XCTestCase {

    // MARK: - Core Clustering Tests

    func testClusteringAdjacentLinesMergesIntoSingleBlock() {
        let line1 = OCRLine(text: "红烧", boundingBox: CGRect(x: 0.1, y: 0.80, width: 0.2, height: 0.05))
        let line2 = OCRLine(text: "牛肉面", boundingBox: CGRect(x: 0.1, y: 0.74, width: 0.25, height: 0.05))

        let clusterer = SpatialTextClusterer()
        let blocks = clusterer.cluster(lines: [line1, line2], lineSpacingThreshold: 0.03)

        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks.first?.mergedText, "红烧牛肉面")
        XCTAssertEqual(blocks.first?.rawLines, ["红烧", "牛肉面"])
        XCTAssertEqual(blocks.first?.boundingBox.minX, 0.1)
        XCTAssertEqual(blocks.first?.boundingBox.minY, 0.74)
        XCTAssertEqual(blocks.first?.boundingBox.maxY, 0.85)
    }

    func testDistantLinesRemainSeparateBlocks() {
        let line1 = OCRLine(text: "Header", boundingBox: CGRect(x: 0.1, y: 0.9, width: 0.3, height: 0.05))
        let line2 = OCRLine(text: "Footer", boundingBox: CGRect(x: 0.1, y: 0.1, width: 0.3, height: 0.05))

        let clusterer = SpatialTextClusterer()
        let blocks = clusterer.cluster(lines: [line1, line2], lineSpacingThreshold: 0.05)

        XCTAssertEqual(blocks.count, 2)
        XCTAssertEqual(blocks[0].mergedText, "Header")
        XCTAssertEqual(blocks[1].mergedText, "Footer")
    }

    func testEmptyInputReturnsEmptyArray() {
        let clusterer = SpatialTextClusterer()
        let blocks = clusterer.cluster(lines: [])

        XCTAssertTrue(blocks.isEmpty)
    }

    func testSingleLineReturnsSingleBlock() {
        let line = OCRLine(text: "Selamat Datang", boundingBox: CGRect(x: 0.2, y: 0.5, width: 0.4, height: 0.06))
        let clusterer = SpatialTextClusterer()
        let blocks = clusterer.cluster(lines: [line])

        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks.first?.mergedText, "Selamat Datang")
        XCTAssertEqual(blocks.first?.rawLines, ["Selamat Datang"])
        XCTAssertEqual(blocks.first?.boundingBox, line.boundingBox)
    }

    func testClusteringLatinLinesAddsSpaces() {
        let line1 = OCRLine(text: "Special", boundingBox: CGRect(x: 0.2, y: 0.80, width: 0.3, height: 0.04))
        let line2 = OCRLine(text: "Lunch Menu", boundingBox: CGRect(x: 0.2, y: 0.74, width: 0.35, height: 0.04))

        let clusterer = SpatialTextClusterer()
        let blocks = clusterer.cluster(lines: [line1, line2], lineSpacingThreshold: 0.03)

        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks.first?.mergedText, "Special Lunch Menu")
        XCTAssertEqual(blocks.first?.rawLines, ["Special", "Lunch Menu"])
    }

    func testHorizontallyDisjointColumnsDoNotMerge() {
        // Two columns side-by-side at the same vertical height
        let column1 = OCRLine(text: "Column 1 Item", boundingBox: CGRect(x: 0.05, y: 0.70, width: 0.35, height: 0.05))
        let column2 = OCRLine(text: "Column 2 Item", boundingBox: CGRect(x: 0.55, y: 0.70, width: 0.35, height: 0.05))

        let clusterer = SpatialTextClusterer()
        let blocks = clusterer.cluster(lines: [column1, column2], lineSpacingThreshold: 0.05)

        XCTAssertEqual(blocks.count, 2)
        // Ordered left-to-right when Y is the same
        XCTAssertEqual(blocks[0].mergedText, "Column 1 Item")
        XCTAssertEqual(blocks[1].mergedText, "Column 2 Item")
    }

    func testMultiLineParagraphChainsTogether() {
        // 3 consecutive lines of Chinese text with small vertical gap
        let line1 = OCRLine(text: "精选新鲜食材", boundingBox: CGRect(x: 0.1, y: 0.80, width: 0.4, height: 0.04))
        let line2 = OCRLine(text: "传统工艺熬制", boundingBox: CGRect(x: 0.1, y: 0.74, width: 0.4, height: 0.04))
        let line3 = OCRLine(text: "浓郁鲜香汤底", boundingBox: CGRect(x: 0.1, y: 0.68, width: 0.4, height: 0.04))

        let clusterer = SpatialTextClusterer()
        let blocks = clusterer.cluster(lines: [line1, line2, line3], lineSpacingThreshold: 0.03)

        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks.first?.mergedText, "精选新鲜食材传统工艺熬制浓郁鲜香汤底")
        XCTAssertEqual(blocks.first?.rawLines.count, 3)
    }

    // MARK: - Character CJK Extension Tests

    func testCJKCharacterDetection() {
        XCTAssertTrue(Character("中").isCJK)
        XCTAssertTrue(Character("文").isCJK)
        XCTAssertTrue(Character("面").isCJK)
        XCTAssertTrue(Character("あ").isCJK) // Hiragana
        XCTAssertTrue(Character("ア").isCJK) // Katakana
        XCTAssertTrue(Character("한").isCJK) // Hangul
        XCTAssertTrue(Character("。").isCJK) // CJK punctuation
        XCTAssertFalse(Character("A").isCJK)
        XCTAssertFalse(Character("z").isCJK)
        XCTAssertFalse(Character("1").isCJK)
        XCTAssertFalse(Character(" ").isCJK)
        XCTAssertFalse(Character(".").isCJK)
    }
}
