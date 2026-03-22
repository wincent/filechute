import os

public enum Log {
  private static let subsystem = "dev.wincent.Filechute"

  private static func osLogger(for category: LogCategory) -> Logger {
    Logger(subsystem: subsystem, category: category.rawValue)
  }

  public static func debug(_ message: String, category: LogCategory = .general) {
    osLogger(for: category).debug("\(message, privacy: .public)")
    Task { @MainActor in
      LogStore.shared.append(level: .debug, category: category, message: message)
    }
  }

  public static func info(_ message: String, category: LogCategory = .general) {
    osLogger(for: category).info("\(message, privacy: .public)")
    Task { @MainActor in
      LogStore.shared.append(level: .info, category: category, message: message)
    }
  }

  public static func error(_ message: String, category: LogCategory = .general) {
    osLogger(for: category).error("\(message, privacy: .public)")
    Task { @MainActor in
      LogStore.shared.append(level: .error, category: category, message: message)
    }
  }
}
