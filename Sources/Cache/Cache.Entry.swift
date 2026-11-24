extension Cache {

    @usableFromInline
    struct Entry {
        @usableFromInline
        let number: UInt64

        @usableFromInline
        let state: State

        @inlinable
        package init(number: UInt64, state: State) {
            self.number = number
            self.state = state
        }
    }
}
