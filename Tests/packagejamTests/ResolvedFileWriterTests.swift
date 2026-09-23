import Foundation
import Testing
@testable import packagejam

@Suite struct ResolvedFileWriterTests {
    private func withScratchFile(_ body: (String) throws -> Void) throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try body(dir.appendingPathComponent("Package.resolved").path)
    }

    @Test func preservesExistingOriginHashAndVersion() throws {
        try withScratchFile { path in
            let existing = """
            {"originHash":"abc123","pins":[{"identity":"old","state":{"version":"1.0.0"}}],"version":3}
            """
            try existing.write(toFile: path, atomically: true, encoding: .utf8)

            try ResolvedFileWriter.write(newPins: [["identity": "new", "state": ["version": "2.0.0"]]], toResolvedFileAt: path)

            let written = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: path))) as? [String: Any]
            #expect(written?["originHash"] as? String == "abc123")
            #expect(written?["version"] as? Int == 3)
            let pins = written?["pins"] as? [[String: Any]]
            #expect(pins?.count == 1)
            #expect((pins?.first?["identity"] as? String) == "new")
        }
    }

    @Test func startsFromBareV2DocumentWhenNoFileExistsYet() throws {
        try withScratchFile { path in
            try ResolvedFileWriter.write(newPins: [["identity": "new", "state": ["version": "1.0.0"]]], toResolvedFileAt: path)

            let written = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: path))) as? [String: Any]
            #expect(written?["version"] as? Int == 2)
            #expect(written?["originHash"] == nil)
        }
    }

    @Test func doesNotEscapeForwardSlashesInOutput() throws {
        try withScratchFile { path in
            try ResolvedFileWriter.write(
                newPins: [["identity": "new", "location": "https://github.com/example/SomePackage"]],
                toResolvedFileAt: path
            )
            let text = try String(contentsOf: URL(fileURLWithPath: path), encoding: .utf8)
            #expect(text.contains("https://github.com/example/SomePackage"))
            #expect(!text.contains("\\/"))
        }
    }

    @Test func endsWithTrailingNewline() throws {
        try withScratchFile { path in
            try ResolvedFileWriter.write(newPins: [], toResolvedFileAt: path)
            let text = try String(contentsOf: URL(fileURLWithPath: path), encoding: .utf8)
            #expect(text.hasSuffix("\n"))
        }
    }
}
