import Foundation
import Testing
@testable import Eskele

// MARK: - Policy

@Test func eachPolicySurvivesTheRoundTripThroughSparkle() {
    for policy in UpdatePolicy.allCases {
        let back = UpdatePolicy(
            checksAutomatically: policy.checksAutomatically,
            downloadsAutomatically: policy.downloadsAutomatically)
        #expect(back == policy)
    }
}

@Test func thePoliciesAreSparklesThreeDistinctStates() {
    #expect(UpdatePolicy(checksAutomatically: true, downloadsAutomatically: true) == .automatic)
    #expect(UpdatePolicy(checksAutomatically: true, downloadsAutomatically: false) == .ask)
    #expect(UpdatePolicy(checksAutomatically: false, downloadsAutomatically: false) == .manual)
}

/// Downloading is only ever done after a scheduled check, so with checks off the download switch
/// changes nothing. Read back as anything but Manual, the picker would show a policy that is not
/// what happens.
@Test func downloadingWithoutCheckingIsManual() {
    #expect(UpdatePolicy(checksAutomatically: false, downloadsAutomatically: true) == .manual)
}

/// `UpdateService.setPolicy` writes both switches every time, so a policy must say both outright:
/// Ask has to switch downloads *off*, not merely leave them as Automatic set them.
@Test func onlyAutomaticDownloads() {
    #expect(UpdatePolicy.automatic.downloadsAutomatically)
    #expect(!UpdatePolicy.ask.downloadsAutomatically)
    #expect(!UpdatePolicy.manual.downloadsAutomatically)
    #expect(!UpdatePolicy.manual.checksAutomatically)
}

// MARK: - Configuration

private let feed = "https://github.com/hossainalhaidari/eskele/releases/latest/download/appcast.xml"
private let key = "pBZfuQXLRj2Ro+OwqTB3mDRd6b3JaRXxdfbBVGwcrxw="

@Test func aReleaseBuildWithFeedAndKeyUpdates() {
    #expect(UpdateService.isConfigured(["SUFeedURL": feed, "SUPublicEDKey": key]))
}

/// What `build-app.sh` makes of a build it was given no version for: the feed is taken out, so a
/// development copy never offers to replace itself with the published release.
@Test func aBuildWithoutAFeedDoesNotUpdate() {
    #expect(!UpdateService.isConfigured(["SUPublicEDKey": key]))
}

/// The state of the repository until `make update-key` has run: the placeholder is an empty
/// string, and Sparkle would treat an empty key as a misconfigured app and say so in an alert.
@Test func aBuildWithoutAKeyDoesNotUpdate() {
    #expect(!UpdateService.isConfigured(["SUFeedURL": feed]))
    #expect(!UpdateService.isConfigured(["SUFeedURL": feed, "SUPublicEDKey": ""]))
    #expect(!UpdateService.isConfigured(["SUFeedURL": feed, "SUPublicEDKey": "  \n"]))
    #expect(!UpdateService.isConfigured([:]))
}

/// Eskele goes online only when asked. Either key missing would hand the choice back to Sparkle:
/// automatic checks it asks about on the second launch, and the system profile it would then offer
/// to send with them.
@Test func theShippedInfoPlistNeitherChecksNorProfilesOnItsOwn() throws {
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // EskeleTests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // repository root
        .appendingPathComponent("Resources/Info.plist")
    let info = try #require(
        PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: Any])
    #expect(info["SUEnableAutomaticChecks"] as? Bool == false)
    #expect(info["SUEnableSystemProfiling"] as? Bool == false)
}

@Test func theVersionNamesTheBuildSparkleCompares() {
    let info = ["CFBundleShortVersionString": "1.4.0", "CFBundleVersion": "212"]
    #expect(UpdateService.version(info) == "1.4.0 (212)")
    #expect(UpdateService.version([:]) == "? (?)")
}
