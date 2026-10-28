import Darwin
import Foundation

/// Files in places the sandbox can write, which the host reads and
/// replaces without following links: a link or a second name planted
/// there would otherwise hand the sandbox whatever host-only file it
/// pointed at.
enum SandboxFile {
    // MARK: Internal

    /// The file's bytes, nil when there is none; anything but a bounded
    /// regular file with a single name throws.
    static func read(_ path: String, byteLimit: Int, relativeTo directory: Int32 = AT_FDCWD) throws -> Data? {
        let descriptor = unsafe openat(directory, path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard descriptor >= 0 else {
            if errno == ENOENT {
                return nil
            }
            throw SessionServiceError(path + " is not a readable regular file")
        }

        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var attributes = stat()
        guard unsafe fstat(descriptor, &attributes) == 0,
              attributes.st_mode & S_IFMT == S_IFREG, attributes.st_nlink == 1, attributes.st_size <= byteLimit
        else {
            throw SessionServiceError(path + " is not a bounded regular file")
        }

        let data = try handle.read(upToCount: byteLimit + 1) ?? Data()
        guard data.count <= byteLimit else {
            throw SessionServiceError(path + " is not a bounded regular file")
        }

        return data
    }

    /// Rewrites one file in a directory the sandbox can write, unless
    /// it already holds that. The directory is opened without
    /// following a link, the old contents are read as above (nil when
    /// refused) and the new ones land by renaming a fresh file over
    /// the name, which replaces a link rather than writing through it.
    static func update(_ name: String, in directory: String, contents: (_ existing: String?) -> String) {
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        let folder = unsafe open(directory, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard folder >= 0 else {
            return
        }

        defer { close(folder) }
        let existing = (try? read(name, byteLimit: updateByteLimit, relativeTo: folder))
            .flatMap { String(data: $0, encoding: .utf8) }
        let replacement = contents(existing)
        guard replacement != existing else {
            return
        }

        let temporary = "." + name + "." + UUID().uuidString
        let descriptor = unsafe openat(folder, temporary, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o644)
        guard descriptor >= 0 else {
            return
        }

        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        let written = (try? handle.write(contentsOf: Data(replacement.utf8))) != nil
        try? handle.close()
        guard written, unsafe renameat(folder, temporary, folder, name) == 0 else {
            _ = unsafe unlinkat(folder, temporary, 0)
            return
        }
    }

    // MARK: Private

    /// Far beyond anything the app publishes, so only a planted file
    /// reaches it.
    private static let updateByteLimit = 1_048_576
}
