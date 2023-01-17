//
//  ContentView.swift
//  GitHubClientWithInjectable
//
//  Created by Franco Bellu on 17/1/23.
//

import SwiftUI
import UIKit
import SafariServices

// MARK: - GitHub Api client dependency
struct GitHub {
    struct Repo: Decodable, Identifiable {
        var id: UUID { UUID()}
        var archived: Bool
        var description: String?
        var htmlUrl: URL
        var name: String
        var pushedAt: Date?
    }

    // if GitHub is declared as class
//    required init(fetchReposA: @escaping () async throws -> [GitHub.Repo] = {try await dataTask("orgs/pointfreeco/repos")}) {
//        self.fetchReposA = fetchReposA
//    }

    var fetchReposA: () async throws -> [GitHub.Repo] = {
        try await dataTask("orgs/pointfreeco/repos")
    }
}

extension GitHub  {
    enum NetWorkingError: Error {
        case nonHttpResponse
        case non2XXStatusCode
    }
}

// MARK: - GitHub Mock
extension GitHub {
    static func mock(
        fetchReposA:  @escaping () async throws -> [GitHub.Repo] =  { [
            GitHub.Repo(
                archived: false,
                description: "Blob's blog",
                htmlUrl: URL(string: "https://www.pointfree.co")!,
                name: "Bloblog",
                pushedAt:  Current.date()
            )
        ]}) -> Self {
            Self(fetchReposA: fetchReposA)
        }

    static func error(fetchReposA:  @escaping () async throws -> [GitHub.Repo] =  { throw NetWorkingError.nonHttpResponse }) -> Self {
        Self(fetchReposA: fetchReposA)
    }
}

// MARK: - Networking layer


private func dataTask<T: Decodable>(_ path: String) async throws -> T {
    let request = URLRequest(url: URL(string: "https://api.github.com/" + path)!)
    let (data, urlResponse) = try await URLSession.shared.data(for: request)
    switch (data, urlResponse) {
    case ( let data, let urlResponse):
        guard let httpResponse = urlResponse as? HTTPURLResponse else { throw GitHub.NetWorkingError.nonHttpResponse }
        switch httpResponse.statusCode {
        case 200 ..< 299:
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZZZZZ"
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .formatted(formatter)
            decoder.keyDecodingStrategy = .convertFromSnakeCase

            return try decoder.decode(T.self, from: data)
        default:
            throw GitHub.NetWorkingError.non2XXStatusCode
        }
    }
}

// MARK: - Analytics dependency
struct Analytics {
  struct Event {
    var name: String
    var properties: [String: String]

    static func tappedRepo(_ repo: GitHub.Repo) -> Event {
      return Event(
        name: "tapped_repo",
        properties: [
          "repo_name": repo.name,
          "build": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown",
          "release": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown",
          "screen_height": String(describing: UIScreen.main.bounds.height),
          "screen_width": String(describing: UIScreen.main.bounds.width),
          "system_name": UIDevice.current.systemName,
          "system_version": UIDevice.current.systemVersion,
          ]
      )
    }
  }

  var track = track(_:)
}

private func track(_ event: Analytics.Event) {
  print("Tracked", event)
}

// MARK: - Environment holding all the dependencies.
struct Environment {
  var analytics = Analytics()
  var date: () -> Date = Date.init
}

import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack {
            ReposView()
                .environment(\.gitHub, GitHub.error())
//                .injectedValue(\.gitHub, value: .error())
            ReposView()
//                .environment(\.gitHub, GitHub.error())
                .environment(\.gitHub, GitHub.mock())
        }
    }
}

struct SFSafariViewWrapper: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: UIViewControllerRepresentableContext<Self>) -> SFSafariViewController {
        return SFSafariViewController(url: url)
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: UIViewControllerRepresentableContext<SFSafariViewWrapper>) {
        return
    }
}

enum NavState {
    case repoList
    case showRepo(repo: GitHub.Repo)
    case isGitHubError(error: GitHub.NetWorkingError)
}

struct ReposView: View {
    @SwiftUI.Environment(\.gitHub) var gitHub
    @State var repos: [GitHub.Repo] = []
    @State private var navState: NavState = .repoList

//    init(gitHub: GitHub = InjectedValues[\.gitHub] ) {
//        self.gitHub = gitHub
//    }

    var body: some View {
        NavigationView{
            switch navState {
            case .repoList:
                List(repos) { repo in
                    Button {
                        navState = .showRepo(repo: repo)
                        Current.analytics.track(.tappedRepo(repo))
                    } label: {
                        VStack{
                            Text(repo.name)
                                .padding()
                            HStack {
                                Text(repo.description?.prefix(1) ?? "❗️")

                                Text(((repo.description?.description.dropFirst(1)) ?? ""))
                                Spacer()
                                if let pushedAt = repo.pushedAt {
                                    Text(timeAgoSince(pushedAt))
                                }
                            }
                        }
                    }
                } .navigationBarTitle("Point-Free Repos")
            case .showRepo( let repo):
                SFSafariViewWrapper(url: repo.htmlUrl)
            case .isGitHubError(let error):
                Text(error.localizedDescription)
            }
        }
        .background(Color.white)
        .task {
            do {
                print("A")
                repos = try await gitHub.fetchReposA()
                    .filter { !$0.archived }
                    .sorted{
                        guard let lhs = $0.pushedAt, let rhs = $1.pushedAt else { return false }
                        return lhs > rhs
                    }
            }
            catch let error as GitHub.NetWorkingError {
                navState = .isGitHubError(error: error)
            } catch {
                print("other")
            }
        }
    }

    func timeAgoSince(_ date: Date) -> String {
        let dateComponentsFormatter = DateComponentsFormatter()
        dateComponentsFormatter.allowedUnits = [.day, .hour, .minute, .second]
        dateComponentsFormatter.maximumUnitCount = 1
        dateComponentsFormatter.unitsStyle = .abbreviated

        return dateComponentsFormatter.string(from: date, to: Current.date()) ?? ""
    }
}



// MARK: - Analytics dependency Mocks
//extension Analytics {
//  static let mock = Analytics(track: { event in
//    print("Mock track", event)
//  })
//}
//
//// MARK: - Date dependency Mocks
//extension Date {
//    static let mock = { Date(timeIntervalSinceReferenceDate: 557152051) }
//}
//
//// MARK: - Environment dependency container mock
//extension Environment {
//  static let mock = Environment(
//    analytics: .mock,
//    date: Date.mock
////    gitHub: .mock,
////    networkProvider: .mock
//  )
//}


// MARK: - THE PROGRAM

// MARK: -  Environment global mutable instance.

var Current = Environment()

//Current.gitHub = GitHub(fetchReposA: { throw NetWorkingError.nonHttpResponse })

//Current.date = { Date(timeIntervalSinceReferenceDate: 557152051)}

// repo uses DI to inject Current dependencies
//let reposViewController = ReposViewController(
//    gitHub: Current.gitHub,
//    date: {
//        Current.date()
////        Date(timeIntervalSinceReferenceDate: 557152051)
//    },
//    analytics: Current.analytics
//)

// repo uses Current dependencies directly
//let reposViewController = ReposViewControllerUsingCurrent()


//public protocol InjectionKey {
//
//    /// The associated type representing the type of the dependency injection key's value.
//    associatedtype Value
//
//    /// The default value for the dependency injection key.
//    static var currentValue: Self.Value { get set }
//}
//
//private struct GitHubKey: InjectionKey {
//    static var currentValue: GitHub = GitHub()
//}
//
//extension InjectedValues {
//    var gitHub: GitHub {
//        get { Self[GitHubKey.self] }
//        set { Self[GitHubKey.self] = newValue }
//    }
//}
//
///// Provides access to dependencies injected ( Using @Injected). Dependencies are created as global mutable state.
//struct InjectedValues {
//
//    /// This is only used as an accessor to the computed properties within extensions of `InjectedValues`.
//    private static var current = InjectedValues()
//
//    /// A static subscript for updating the `currentValue` of `InjectionKey` instances.
//    static subscript<K>(key: K.Type) -> K.Value where K : InjectionKey {
//        get { key.currentValue }
//        set { key.currentValue = newValue }
//    }
//
//    /// A static subscript accessor for updating and references dependencies directly.
//    static subscript<T>(_ keyPath: WritableKeyPath<InjectedValues, T>) -> T {
//        get { current[keyPath: keyPath] }
//        set { current[keyPath: keyPath] = newValue }
//    }
//}
//
//@propertyWrapper
//struct Injected<T> {
//    private let keyPath: WritableKeyPath<InjectedValues, T>
//    var wrappedValue: T {
//        get { InjectedValues[keyPath] }
//        set { InjectedValues[keyPath] = newValue }
//    }
//
//    init(_ keyPath: WritableKeyPath<InjectedValues, T>) {
//        self.keyPath = keyPath
//    }
//}


struct ContentView_Previews: PreviewProvider {

    static var previews: some View {
//        InjectedValues[\.gitHub] = .mock()
        return ContentView()
//            .environment(\.gitHub, .error()) //.injectedValue(\.gitHub, value: .error())
    }
}

//extension View {
//    func injectedValue<V>(_ keyPath: WritableKeyPath<InjectedValues, V>, value: V) -> some View{
//        InjectedValues[keyPath] = value
//        return self
//    }
//}

private struct GitHubKey: EnvironmentKey {
  static let defaultValue = GitHub()
}

extension EnvironmentValues {
  var gitHub: GitHub  {
    get { self[GitHubKey.self] }
    set { self[GitHubKey.self] = newValue }
  }
}

//extension View {
//    func setEnvironmentDependency(_ gitHub: GitHub) -> some View {
//      environment(\.gitHub, gitHub)
//  }
//}
