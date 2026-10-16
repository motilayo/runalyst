import XCTest
@testable import Runalyst

final class PaceFormatterTests: XCTestCase {
    override func tearDown() {
        super.tearDown()
        UserDefaults.standard.set(true, forKey: "useMetricSystem")
    }

    func testFormatPaceMetric() {
        UserDefaults.standard.set(true, forKey: "useMetricSystem")

        let pace1 = PaceFormatter.formatPace(secondsPerKilometer: 300) // 5:00/km
        XCTAssertEqual(pace1, "5:00/km")

        let pace2 = PaceFormatter.formatPace(secondsPerKilometer: 315) // 5:15/km
        XCTAssertEqual(pace2, "5:15/km")
    }

    func testFormatPaceImperial() {
        UserDefaults.standard.set(false, forKey: "useMetricSystem")
        defer { UserDefaults.standard.set(true, forKey: "useMetricSystem") }

        // 300 sec/km * 1.609344 = 482.8032 sec/mi -> 8 min 3 sec -> 8:03/mi
        let pace1 = PaceFormatter.formatPace(secondsPerKilometer: 300)
        XCTAssertEqual(pace1, "8:03/mi")
    }
}
