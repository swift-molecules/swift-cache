extension Cache {

    @usableFromInline
    enum Action {
        case returnValue(Value)

        // swiftlint:disable:next no_any_protocol_existential  // reason: Cache retains caller-defined compute errors for later delivery.
        case throwError(any Swift::Error)

        case wait(Key, Entry)
        case compute(Key, Entry)
    }
}
