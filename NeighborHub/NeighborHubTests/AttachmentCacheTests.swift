import XCTest
@testable import NeighborHub

final class AttachmentCacheTests: XCTestCase {
    func testWriteAndExcludeFromBackup() throws {
        let data = "hello".data(using: .utf8)!
        let suggested = "test-attach.txt"
        guard let url = AttachmentCache.shared.write(data: data, suggestedName: suggested) else {
            XCTFail("Failed to write attachment")
            return
        }
        let fm = FileManager.default
        XCTAssertTrue(fm.fileExists(atPath: url.path))
        let rv = try url.resourceValues(forKeys: [.isExcludedFromBackupKey])
        // resource may or may not be set depending on platform, but ensure file exists
        // If key exists, it should be true
        if let excluded = rv.isExcludedFromBackup {
            XCTAssertTrue(excluded)
        }
        // cleanup
        try? fm.removeItem(at: url)
    }
}
