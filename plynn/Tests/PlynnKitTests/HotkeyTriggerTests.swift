import XCTest
@testable import PlynnKit

final class HotkeyTriggerTests: XCTestCase {
    /// The invariant that matters is about the keys a user can CHOOSE for
    /// dictation. `option` is the Chewie key and deliberately shares a keycode
    /// with `rightOption`, which is why that one is not selectable.
    func testSelectableTriggersHaveDistinctKeycodes() {
        let codes = Set(HotkeyTrigger.selectable.map(\.keycode))
        XCTAssertEqual(
            codes.count, HotkeyTrigger.selectable.count, "selectable keycodes must not collide")
    }

    func testChewieKeyIsNotOfferedForDictation() {
        XCTAssertFalse(HotkeyTrigger.selectable.contains(.option))
        XCTAssertFalse(HotkeyTrigger.selectable.contains(.rightOption))
    }

    /// Either Option wakes Chewie.
    func testOptionMatchesBothSides() {
        XCTAssertTrue(HotkeyTrigger.option.matches(keycode: 58))
        XCTAssertTrue(HotkeyTrigger.option.matches(keycode: 61))
        XCTAssertFalse(HotkeyTrigger.option.matches(keycode: 63))
    }

    func testMatchesOnlyItsOwnKeycode() {
        for trigger in HotkeyTrigger.selectable {
            XCTAssertTrue(trigger.matches(keycode: trigger.keycode))
            for other in HotkeyTrigger.selectable where other != trigger {
                XCTAssertFalse(trigger.matches(keycode: other.keycode))
            }
        }
    }

    func testRawValueRoundTrips() {
        for trigger in HotkeyTrigger.allCases {
            XCTAssertEqual(HotkeyTrigger(rawValue: trigger.rawValue), trigger)
        }
    }

    func testDefaultIsFn() {
        XCTAssertEqual(HotkeyTrigger.fn.keycode, 63)
    }

    func testDisplayNamesAreDistinctAndNonEmpty() {
        let names = Set(HotkeyTrigger.allCases.map(\.displayName))
        XCTAssertEqual(names.count, HotkeyTrigger.allCases.count)
        XCTAssertTrue(names.allSatisfy { !$0.isEmpty })
    }
}
