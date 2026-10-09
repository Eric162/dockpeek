import Darwin
import Foundation

/// Holds a process-lifetime lock.
///
/// A stale PID file never establishes ownership.
public final class WorkerLock {
  private let descriptor: Int32

  public init(url: URL) throws {
    descriptor = open(url.path, O_CREAT | O_RDWR | O_CLOEXEC, S_IRUSR | S_IWUSR)
    guard descriptor >= 0 else { throw POSIXError(.EACCES) }
    guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
      close(descriptor)
      throw POSIXError(.EWOULDBLOCK)
    }
  }

  deinit {
    // Release ownership even if a concurrently forked child inherited the fd.
    flock(descriptor, LOCK_UN)
    close(descriptor)
  }
}
