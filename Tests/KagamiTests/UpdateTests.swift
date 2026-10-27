import XCTest
@testable import Kagami

final class UpdateTests: XCTestCase {
    func testPolicyRoundTripsThroughSparkleSwitches() {
        for policy in UpdatePolicy.allCases {
            XCTAssertEqual(
                UpdatePolicy(checksAutomatically: policy.checksAutomatically,
                             downloadsAutomatically: policy.downloadsAutomatically),
                policy)
        }
        // Downloading without checking never happens, so it reads back as manual.
        XCTAssertEqual(UpdatePolicy(checksAutomatically: false, downloadsAutomatically: true), .manual)
    }

    /// A development build has no feed and an unconfigured one has no key; neither may start Sparkle.
    func testUpdaterNeedsBothFeedAndKey() {
        let feed = "https://github.com/hossainalhaidari/kagami/releases/latest/download/appcast.xml"
        XCTAssertTrue(UpdateService.isConfigured(["SUFeedURL": feed, "SUPublicEDKey": "abc="]))
        XCTAssertFalse(UpdateService.isConfigured(["SUPublicEDKey": "abc="]))
        XCTAssertFalse(UpdateService.isConfigured(["SUFeedURL": feed, "SUPublicEDKey": " "]))
    }

    func testVersionShowsBuildNumber() {
        XCTAssertEqual(UpdateService.version(["CFBundleShortVersionString": "0.1.0", "CFBundleVersion": "7"]), "0.1.0 (7)")
    }
}
