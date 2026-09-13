import Observation

@MainActor
@Observable
final class OnboardingViewModel {
    private(set) var page = 0
    var isLastPage: Bool { page == 2 }
    func advance() { page = min(page + 1, 2) }
}
