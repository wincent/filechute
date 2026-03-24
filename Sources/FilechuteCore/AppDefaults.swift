import Foundation

public enum AppDefaults {
  nonisolated(unsafe) public static let shared: UserDefaults = {
    let args = CommandLine.arguments
    if let index = args.firstIndex(of: "-UserDefaultsSuite"),
      index + 1 < args.count
    {
      let suite = args[index + 1]
      return UserDefaults(suiteName: suite) ?? .standard
    }
    return .standard
  }()
}
