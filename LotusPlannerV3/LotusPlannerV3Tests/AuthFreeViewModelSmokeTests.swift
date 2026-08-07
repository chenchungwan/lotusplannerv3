import XCTest
@testable import LotusPlannerV3

@MainActor
final class AuthFreeViewModelSmokeTests: XCTestCase {
    func testCalendarViewModelStartsWithoutNetworkState() {
        let viewModel = CalendarViewModel()

        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.showError)
        XCTAssertFalse(viewModel.qualitySummary(for: .account1).isEmpty)
    }

    func testTasksViewModelStartsWithoutNetworkState() {
        let viewModel = TasksViewModel()

        XCTAssertFalse(viewModel.isLoading)
        XCTAssertTrue(viewModel.account1Tasks.isEmpty)
        XCTAssertTrue(viewModel.account2Tasks.isEmpty)
        XCTAssertFalse(viewModel.qualitySummary(for: .account1).isEmpty)
    }
}
