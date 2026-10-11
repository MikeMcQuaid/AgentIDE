import Darwin
import Foundation

extension AutofixResult {
    /// The sandbox can write this file: refuse links, pipes and unbounded data.
    static func read(path: String) throws -> Self? {
        let descriptor = unsafe open(path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard descriptor >= 0 else {
            if errno == ENOENT {
                return nil
            }
            throw SessionServiceError("The autofix result is not a readable regular file")
        }

        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var attributes = stat()
        guard unsafe fstat(descriptor, &attributes) == 0,
              attributes.st_mode & S_IFMT == S_IFREG, attributes.st_size <= byteLimit,
              let data = try handle.read(upToCount: byteLimit + 1), data.count <= byteLimit
        else {
            throw SessionServiceError("The autofix result is not a bounded regular file")
        }

        return try JSONDecoder().decode(Self.self, from: data)
    }

    private static let byteLimit = 16_384
}
