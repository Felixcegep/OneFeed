import Observation

enum AppDestination: Hashable { case saved, history, sources, settings }

@MainActor
@Observable
final class AppRootViewModel {
    var path: [AppDestination] = []
    func open(_ destination: AppDestination) { path.append(destination) }
}
