import Foundation

extension AutofixResult {
    /// The sandbox can write this file: refuse links, pipes and unbounded data.
    static func read(path: String) throws -> Self? {
        guard let data = try SandboxFile.read(path, byteLimit: byteLimit) else {
            return nil
        }

        return try JSONDecoder().decode(Self.self, from: data)
    }

    private static let byteLimit = 16_384
}
