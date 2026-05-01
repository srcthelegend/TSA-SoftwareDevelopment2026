import XCTest

final class ClothingAssist3UITests: XCTestCase {

    override func setUpWithError() throws {
        // Stop on first failure so UI test errors are easier to debug.
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
    }

    @MainActor
    func testExample() throws {
        let app = XCUIApplication()
        app.launch()
    }

    @MainActor
    func testLaunchPerformance() throws {
        // Keep an eye on launch time regressions.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
