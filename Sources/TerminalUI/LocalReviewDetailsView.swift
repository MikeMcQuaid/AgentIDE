import AgentIDEDomain
import SwiftUI

/// The captured exchange, including failures, in both local review surfaces.
public struct LocalReviewDetailsView: View {
    // MARK: Lifecycle

    public init(review: LocalReview?) {
        self.review = review
    }

    // MARK: Public

    public var body: some View {
        DisclosureGroup("Review log") {
            ScrollView {
                VStack(alignment: .leading, spacing: Self.spacing) {
                    Text("Model: " + (review?.model ?? "CLI default")
                        + " · Effort: " + (review?.effort ?? "CLI default"))
                    Text("Change model and effort in Settings → Review.").foregroundStyle(.secondary)
                    Text(review?.diagnostics ?? "")
                    Text(review?.output ?? "")
                    DisclosureGroup("Input") { Text(review?.input ?? "") }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
            }
            .frame(maxHeight: Self.logHeight)
        }
        .interfaceFont(.body)
        .disabled(review == nil)
    }

    // MARK: Private

    private static let spacing: CGFloat = 8
    private static let logHeight: CGFloat = 180

    private let review: LocalReview?
}
