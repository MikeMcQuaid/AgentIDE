public extension MetadataStore {
    /// Active loops retain their claims; interrupted local collections can retry after launch.
    func resumeFeedbackLoops() {
        update { metadata in
            for key in metadata.pullRequestAutomation.keys {
                guard metadata.pullRequestAutomation[key]?.isAutomatic == true,
                      metadata.pullRequestAutomation[key]?.collection?.isPending == true
                else {
                    continue
                }

                metadata.pullRequestAutomation[key]?.collection = nil
                metadata.pullRequestAutomation[key]?.pending = "Resuming local feedback collection"
            }
        }
    }
}
