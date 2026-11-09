extension Cache {

    public enum Error: Swift::Error, Sendable {

        case computeFailed(any Swift::Error)

        case cancelled
    }
}

extension Cache.Error {

    /// The error a caller sees when a computation ends with `failure`:
    /// `.cancelled` for a `CancellationError`, `.computeFailed` otherwise.
    /// The computing caller and every waiter map through this one place.
    @usableFromInline
    init(failure: any Swift::Error) {
        if failure is CancellationError {
            self = .cancelled
        } else {
            self = .computeFailed(failure)
        }
    }
}
