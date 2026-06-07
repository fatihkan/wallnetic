import XCTest
@testable import Wallnetic

@MainActor
final class SystemAerialInjectorTests: XCTestCase {

    // MARK: - makeAssetEntry

    func testAssetEntryUsesLocalFileURL() {
        let video = URL(fileURLWithPath: "/Users/x/Library/Application Support/com.apple.wallpaper/aerials/videos/ABCD.mov")
        let a = SystemAerialInjector.makeAssetEntry(
            id: "ABCD", label: "My Clip", videoURL: video, thumbnailURL: nil,
            categoryID: "CAT-1", subcategoryID: "SUB-1"
        )
        XCTAssertEqual(a["id"] as? String, "ABCD")
        XCTAssertEqual(a["accessibilityLabel"] as? String, "My Clip")
        XCTAssertEqual(a["url-4K-SDR-240FPS"] as? String, video.absoluteString)
        XCTAssertTrue((a["url-4K-SDR-240FPS"] as? String)?.hasPrefix("file://") ?? false)
        XCTAssertEqual(a["categories"] as? [String], ["CAT-1"])
        XCTAssertEqual(a["subcategories"] as? [String], ["SUB-1"])
        XCTAssertEqual(a["includeInShuffle"] as? Bool, false)
        XCTAssertNil(a["previewImage"])
    }

    func testAssetEntryShotIDMarksOurs() {
        let video = URL(fileURLWithPath: "/v/0123456789ABCDEF.mov")
        let a = SystemAerialInjector.makeAssetEntry(
            id: "0123456789ABCDEF", label: "x", videoURL: video, thumbnailURL: nil,
            categoryID: nil, subcategoryID: nil
        )
        // WN_ prefix + first 8 chars of the id — used to find/remove our asset.
        XCTAssertEqual(a["shotID"] as? String, "WN_01234567")
        XCTAssertEqual(a["categories"] as? [String], [])
        XCTAssertEqual(a["subcategories"] as? [String], [])
    }

    func testAssetEntryIncludesThumbnailWhenGiven() {
        let a = SystemAerialInjector.makeAssetEntry(
            id: "ID", label: "x", videoURL: URL(fileURLWithPath: "/v/ID.mov"),
            thumbnailURL: URL(fileURLWithPath: "/v/ID.jpg"), categoryID: nil, subcategoryID: nil
        )
        XCTAssertEqual(a["previewImage"] as? String, "file:///v/ID.jpg")
    }

    // MARK: - applyIdleAerial

    func testApplyIdleAerialPatchesEveryIdleSlot() throws {
        let sample: [String: Any] = [
            "Displays": [
                "D1": [
                    "Idle": ["Content": ["Choices": [["Provider": "com.apple.wallpaper.choice.color"]], "Shuffle": "$null"]],
                    "Desktop": ["Content": ["Choices": [["Provider": "com.apple.wallpaper.choice.image"]]]]
                ]
            ],
            "SystemDefault": [
                "Idle": ["Content": ["Choices": [["Provider": "com.apple.wallpaper.choice.aerials"]]]]
            ]
        ]
        let plist = try roundTripMutable(sample)
        let cfg = try PropertyListSerialization.data(fromPropertyList: ["assetID": "ASSET-9"], format: .binary, options: 0)

        let count = SystemAerialInjector.applyIdleAerial(
            to: plist, configuration: cfg, optionValues: SystemAerialInjector.aerialOptionValues
        )

        XCTAssertEqual(count, 2, "both Idle slots (Displays/D1 + SystemDefault) should be patched")

        let choice = try XCTUnwrap(idleChoice(plist, path: ["Displays", "D1"]))
        XCTAssertEqual(choice["Provider"] as? String, "com.apple.wallpaper.choice.aerials")
        let decoded = try PropertyListSerialization.propertyList(
            from: try XCTUnwrap(choice["Configuration"] as? Data), options: [], format: nil
        ) as? [String: Any]
        XCTAssertEqual(decoded?["assetID"] as? String, "ASSET-9")
    }

    func testApplyIdleAerialLeavesDesktopUntouched() throws {
        let sample: [String: Any] = [
            "SystemDefault": [
                "Desktop": ["Content": ["Choices": [["Provider": "com.apple.wallpaper.choice.image"]]]],
                "Idle": ["Content": ["Choices": [["Provider": "com.apple.wallpaper.choice.color"]]]]
            ]
        ]
        let plist = try roundTripMutable(sample)
        let cfg = try PropertyListSerialization.data(fromPropertyList: ["assetID": "A"], format: .binary, options: 0)
        _ = SystemAerialInjector.applyIdleAerial(to: plist, configuration: cfg, optionValues: SystemAerialInjector.aerialOptionValues)

        let desktop = ((((plist["SystemDefault"] as? NSDictionary)?["Desktop"] as? NSDictionary)?["Content"] as? NSDictionary)?["Choices"] as? NSArray)?[0] as? NSDictionary
        XCTAssertEqual(desktop?["Provider"] as? String, "com.apple.wallpaper.choice.image", "Desktop must stay as-is")
    }

    func testAerialOptionValuesIsValidPlist() throws {
        let pl = try PropertyListSerialization.propertyList(
            from: SystemAerialInjector.aerialOptionValues, options: [], format: nil
        )
        XCTAssertNotNil(pl as? [String: Any])
    }

    // MARK: - Helpers

    private func roundTripMutable(_ obj: [String: Any]) throws -> NSMutableDictionary {
        let data = try PropertyListSerialization.data(fromPropertyList: obj, format: .binary, options: 0)
        return try XCTUnwrap(PropertyListSerialization.propertyList(
            from: data, options: [.mutableContainersAndLeaves], format: nil
        ) as? NSMutableDictionary)
    }

    private func idleChoice(_ plist: NSMutableDictionary, path: [String]) -> NSDictionary? {
        var node: Any? = plist
        for key in path { node = (node as? NSDictionary)?[key] }
        let content = (node as? NSDictionary)?["Idle"] as? NSDictionary
        let choices = (content?["Content"] as? NSDictionary)?["Choices"] as? NSArray
        return choices?[0] as? NSDictionary
    }
}
