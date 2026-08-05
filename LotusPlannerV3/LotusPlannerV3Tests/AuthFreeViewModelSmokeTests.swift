import XCTest
@testable import LotusPlannerV3

@MainActor
final class AuthFreeViewModelSmokeTests: XCTestCase {
    func testCalendarViewModelStartsWithoutNetworkState() {
        let viewModel = CalendarViewModel()

        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.showError)
        XCTAssertFalse(viewModel.qualitySummary(for: .personal).isEmpty)
    }

    func testTasksViewModelStartsWithoutNetworkState() {
        let viewModel = TasksViewModel()

        XCTAssertFalse(viewModel.isLoading)
        XCTAssertTrue(viewModel.personalTasks.isEmpty)
        XCTAssertTrue(viewModel.professionalTasks.isEmpty)
        XCTAssertFalse(viewModel.qualitySummary(for: .personal).isEmpty)
    }
}
