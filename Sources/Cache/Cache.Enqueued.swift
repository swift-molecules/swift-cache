#if DEBUG
    extension Cache {
        /// What a test is told by that a waiter has queued.
        struct Enqueued: Sendable {
            var call: (@Sendable () -> Void)?
        }
    }
#endif
