extension Cache.Entry {

    @usableFromInline

    enum State: @unchecked Sendable {

        case empty

        case computing(Waiters)

        case ready(Value)

        // swiftlint:disable:next no_any_protocol_existential  // reason: Cache retains caller-defined compute errors for later delivery.
        case failed(any Swift::Error)

    }
}
