import Foundation
import Darwin

public final class StandaloneInstanceLock {
    private let descriptor: Int32
    public init(url: URL) throws {
        let fd = Darwin.open(url.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw POSIXError(.EACCES) }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            Darwin.close(fd)
            throw POSIXError(.EWOULDBLOCK)
        }
        descriptor = fd
    }
    deinit { flock(descriptor, LOCK_UN); Darwin.close(descriptor) }
}
