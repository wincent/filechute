import Foundation

public enum ObjectStoreError: Error, LocalizedError {
  case objectNotFound(ContentHash)
  case hashMismatch(expected: ContentHash, actual: ContentHash)
  case writeFailed(URL, underlying: any Error)

  public var errorDescription: String? {
    switch self {
    case .objectNotFound(let hash):
      "Object not found: \(hash)"
    case .hashMismatch(let expected, let actual):
      "Hash mismatch: expected \(expected), got \(actual)"
    case .writeFailed(let url, let underlying):
      "Failed to write to \(url): \(underlying)"
    }
  }
}

public enum DatabaseError: Error, LocalizedError {
  case openFailed(String)
  case prepareFailed(String)
  case executionFailed(String)
  case notFound
  case constraintViolation(String)

  public var errorDescription: String? {
    switch self {
    case .openFailed(let msg): "Failed to open database: \(msg)"
    case .prepareFailed(let msg): "Failed to prepare statement: \(msg)"
    case .executionFailed(let msg): "Execution failed: \(msg)"
    case .notFound: "Record not found"
    case .constraintViolation(let msg): "Constraint violation: \(msg)"
    }
  }
}
