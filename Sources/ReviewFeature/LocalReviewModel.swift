import AgentIDEData
import AgentIDEDomain
import Foundation
import Observation

@Observable
@MainActor
final class LocalReviewModel {
    // MARK: Lifecycle

    init(
        review: LocalReview?,
        reviewer: AgentKind,
        run: @escaping Run,
        revision: @escaping () async throws -> String,
        save: @escaping (LocalReview) -> Void,
    ) {
        self.review = review
        error = review?.failure
        self.reviewer = reviewer
        reviewInstructions = review?.instructions ?? LocalReviewInput.instructions
        self.run = run
        self.revision = revision
        self.save = save
    }

    deinit {
        // No resources to release.
    }

    convenience init(service: SessionService, worktreePath: String) {
        self.init(
            review: service.localReview(worktreePath: worktreePath),
            reviewer: service.localReviewer(worktreePath: worktreePath),
            run: { files, reviewer, instructions in
                try await service.runLocalReview(
                    files: files, worktreePath: worktreePath, reviewer: reviewer, instructions: instructions,
                )
            },
            revision: { try await service.localReviewRevision(worktreePath: worktreePath) },
            save: { service.saveLocalReview($0, worktreePath: worktreePath) },
        )
    }

    // MARK: Internal

    typealias Run = ([DiffFile], AgentKind, String) async throws -> LocalReview

    var reviewer: AgentKind
    private(set) var isRunning = false
    private(set) var isPreparing = false
    private(set) var isOutdated = false
    private(set) var error: String?
    var reviewInstructions: String
    var prompt = ""
    var showsPrompt = false

    var isBusy: Bool {
        isRunning || isPreparing
    }

    var review: LocalReview? {
        didSet {
            if let review {
                save(review)
            }
        }
    }

    var canPrepare: Bool {
        guard let review else {
            return false
        }

        return review.failure == nil && review.threads.isEmpty == false
            && review.remaining > 0 && isOutdated == false && isBusy == false && error == nil
    }

    func update(files: [DiffFile]) {
        guard let review else {
            return
        }

        isOutdated = revisionChanged
            || review.snapshot != LocalReviewInput.fingerprint(LocalReviewInput.snapshot(files: files))
    }

    func start(files: [DiffFile]) async {
        guard isBusy == false else {
            return
        }

        isRunning = true
        error = nil
        prompt = ""
        defer { isRunning = false }
        do {
            review = try await run(files, reviewer, reviewInstructions)
            error = review?.failure
            revisionChanged = try await review?.revision != revision()
            update(files: files)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func prepare(threadID: String? = nil, files: () async -> [DiffFile]) async -> Bool {
        guard canPrepare, let review else {
            return false
        }

        isPreparing = true
        error = nil
        defer { isPreparing = false }
        await update(files: files())
        guard isOutdated == false else {
            return false
        }

        do {
            guard try await review.revision == revision() else {
                revisionChanged = true
                isOutdated = true
                return false
            }
            guard let prepared = review.prompt(for: threadID) else {
                return false
            }

            prompt = prepared
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    func toggleResolved(_ threadID: String) {
        guard isBusy == false, var review, let index = review.threads.firstIndex(where: { $0.id == threadID }) else {
            return
        }

        let thread = review.threads[index]
        review.threads[index] = ReviewThread(
            id: thread.id,
            path: thread.path,
            line: thread.line,
            isResolved: thread.isResolved == false,
            comments: thread.comments,
            resolveID: thread.resolveID,
        )
        self.review = review
    }

    // MARK: Private

    private let run: Run
    private var revisionChanged = false
    private let revision: () async throws -> String
    private let save: (LocalReview) -> Void
}
