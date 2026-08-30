import XCTest
@testable import SevenZipMac

final class DocumentRecognitionServiceTests: XCTestCase {
    func testSDKIsLinked() {
        XCTAssertEqual(DocumentRecognitionService.sdkVersion, "0.1.0")
    }
}
