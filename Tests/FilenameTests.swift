import Foundation
import Testing
@testable import Pad

@Suite struct PadFilenameTests {
    @Test func defaultPatternUsesGregorianDateAndPaddedNumber() throws {
        let date = try #require(ISO8601DateFormatter().date(from: "2026-09-25T10:00:00Z"))
        let utc = try #require(TimeZone(secondsFromGMT: 0))
        #expect(try PadFilename.name(parts: PadFilename.defaultParts, format: .txt,
                                        now: date, number: 1, timeZone: utc) == "2026-09-25-001.txt")
        #expect(try PadFilename.name(parts: PadFilename.defaultParts, format: .md,
                                        now: date, number: 1204, timeZone: utc) == "2026-09-25-1204.md")
    }

    @Test func customPatternPreservesOrderAndLiteralText() throws {
        let date = try #require(ISO8601DateFormatter().date(from: "2026-01-02T10:00:00Z"))
        let utc = try #require(TimeZone(secondsFromGMT: 0))
        let parts: [PadNamePart] = [.literal("Notes "), .token(.number), .literal(" - "), .token(.day), .token(.month)]
        #expect(try PadFilename.name(parts: parts, format: .md, now: date,
                                        number: 12, timeZone: utc) == "Notes 012 - 0201.md")
        let encoded = try JSONEncoder().encode(parts)
        #expect(try JSONDecoder().decode([PadNamePart].self, from: encoded) == parts)
    }

    @Test func danglingSymlinkCountsAsAnExistingFilename() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "pad-filenames-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createSymbolicLink(atPath: folder.appending(path: "001.txt").path,
                                                   withDestinationPath: folder.appending(path: "missing.txt").path)
        let available = try PadFilename.available(in: folder, parts: [.token(.number)], format: .txt, number: 1)
        #expect(available.url.lastPathComponent == "002.txt")
        #expect(available.number == 2)
    }
}
