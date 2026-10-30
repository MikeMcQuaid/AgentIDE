import Foundation

/// JSON records may span SSH packets; frame sizes are bounded before decoding.
public struct RemoteLines: Sendable {
    // MARK: Lifecycle

    /// Starts with no buffered bytes.
    public init() {
        // The buffer starts empty.
    }

    // MARK: Public

    /// Returns complete UTF-8 records, retaining any partial final line.
    public mutating func append(_ data: Data) throws -> [String] {
        var lines = [String]()
        for byte in data {
            if byte == Self.newline {
                guard let line = String(data: pending, encoding: .utf8) else {
                    throw RemoteError("The remote record is not UTF-8.")
                }

                lines.append(line)
                pending.removeAll(keepingCapacity: true)
            } else {
                guard pending.count < Self.maximumRecordBytes else {
                    throw RemoteError("The remote record is too large.")
                }

                pending.append(byte)
            }
        }
        return lines
    }

    // MARK: Private

    private static let maximumRecordBytes = 8_388_608
    private static let newline: UInt8 = 10

    private var pending: Data = .init()
}
