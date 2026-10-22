extension Cache {

    public enum Error: Swift::Error, Sendable {

        // swiftlint:disable:next no_any_protocol_existential  // reason: Cache reports caller-defined compute errors.
        case computeFailed(any Swift::Error)

        case cancelled
    }
}
