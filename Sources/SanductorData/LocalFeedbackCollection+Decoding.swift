import SanductorDomain

extension LocalFeedbackCollection {
    /// Retains captured reviews when older metadata omits default fields.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        revision = try container.decode(String.self, forKey: .revision)
        configuration = try container.decode(String.self, forKey: .configuration)
        isPending = try container.decodeIfPresent(Bool.self, forKey: .isPending) ?? true
        review = try container.decodeIfPresent(LocalReview.self, forKey: .review)
        failure = try container.decodeIfPresent(String.self, forKey: .failure)
    }

    // Coding keys match the existing synthesised spelling.
    // swiftlint:disable explicit_enum_raw_value
    enum CodingKeys: String, CodingKey {
        case id
        case revision
        case configuration
        case isPending
        case review
        case failure
    }
    // swiftlint:enable explicit_enum_raw_value
}
